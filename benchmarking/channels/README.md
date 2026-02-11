# Channel Proxy Benchmarking

Pure Elixir tools for testing the channel proxy's performance and memory
behaviour. No external dependencies (k6, etc.) — just `elixir` and a running
Lightning instance.

## Prerequisites

- Elixir installed (Mix.install handles all script dependencies)
- A running Lightning instance started as a named Erlang node
- The channel proxy feature enabled (routes at `/channels/:id/*path`)

## Quick Start

Three terminals:

```bash
# Terminal 1 — Mock sink (simulates the downstream HTTP service)
elixir benchmarking/channels/mock_sink.exs

# Terminal 2 — Lightning (as a named node)
iex --sname lightning --cookie bench -S mix phx.server

# Terminal 3 — Load test
elixir --sname loadtest --cookie bench \
  benchmarking/channels/load_test.exs \
  --scenario happy_path --concurrency 20 --duration 30
```

The load test will automatically create a "load-test" project and channel
pointing at the mock sink, then drive traffic through the proxy and report
results.

## Mock Sink (`mock_sink.exs`)

A standalone Bandit HTTP server that accepts all requests and responds according
to the configured mode.

```bash
elixir benchmarking/channels/mock_sink.exs [options]
```

### Options

| Option              | Default                 | Description                |
| ------------------- | ----------------------- | -------------------------- |
| `--port PORT`       | 4001                    | Listen port                |
| `--mode MODE`       | fixed                   | Response mode (see below)  |
| `--status CODE`     | 200                     | HTTP status for fixed mode |
| `--delay MS`        | 0 (fixed), 1000 (delay) | Response delay             |
| `--body-size BYTES` | 256                     | Response body size         |

### Modes

| Mode        | Behaviour                                                                       |
| ----------- | ------------------------------------------------------------------------------- |
| **fixed**   | Returns `--status` after `--delay` with `--body-size` body                      |
| **delay**   | Returns 200 after `--delay` ms (default 1000ms)                                 |
| **timeout** | Accepts connection, never responds                                              |
| **auth**    | 401 if no `Authorization` header, 403 if invalid, 200 for `Bearer test-api-key` |
| **mixed**   | 80% fast 200, 10% slow 200 (2s delay), 10% 503                                  |

### Examples

```bash
# Default: fast 200 responses
elixir benchmarking/channels/mock_sink.exs

# Simulate slow upstream (2s delay)
elixir benchmarking/channels/mock_sink.exs --mode delay --delay 2000

# Simulate flaky upstream
elixir benchmarking/channels/mock_sink.exs --mode mixed

# Large response bodies (5MB)
elixir benchmarking/channels/mock_sink.exs --body-size 5000000

# Require authentication
elixir benchmarking/channels/mock_sink.exs --mode auth
```

## Load Test (`load_test.exs`)

Drives HTTP traffic through the channel proxy, collects metrics, and reports
latency percentiles, throughput, error rates, and BEAM memory usage.

```bash
elixir --sname loadtest --cookie COOKIE \
  benchmarking/channels/load_test.exs [options]
```

**Important:** Must be run as a named Erlang node (`--sname`) so it can connect
to the Lightning BEAM for channel setup and memory sampling.

### Options

| Option                 | Default                 | Description                                         |
| ---------------------- | ----------------------- | --------------------------------------------------- |
| `--target URL`         | `http://localhost:4000` | Lightning base URL                                  |
| `--sink URL`           | `http://localhost:4001` | Mock sink URL (for channel creation)                |
| `--node NODE`          | `lightning@hostname`    | Lightning node name                                 |
| `--cookie COOKIE`      | —                       | Erlang cookie (also settable via `elixir --cookie`) |
| `--channel NAME`       | `load-test`             | Channel name to find/create                         |
| `--scenario NAME`      | `happy_path`            | Test scenario (see below)                           |
| `--concurrency N`      | 10                      | Concurrent virtual users                            |
| `--duration SECS`      | 30                      | Test duration                                       |
| `--payload-size BYTES` | 1024                    | Request body size                                   |
| `--csv PATH`           | —                       | Optional CSV output file                            |

### Scenarios

| Scenario           | Description                                     | Mock sink mode        |
| ------------------ | ----------------------------------------------- | --------------------- |
| **happy_path**     | Sustained POST requests at constant concurrency | `fixed` (default)     |
| **ramp_up**        | Linearly ramp from 1 → N VUs over duration      | `fixed`               |
| **large_payload**  | POST with large request bodies (default 1MB)    | `fixed`               |
| **large_response** | GET requests with large response bodies         | `fixed --body-size N` |
| **mixed_methods**  | Rotate through GET, POST, PUT, PATCH, DELETE    | `fixed`               |
| **slow_sink**      | Measure latency with a slow upstream            | `delay --delay N`     |

### Examples

```bash
# Basic throughput test
elixir --sname lt --cookie bench \
  benchmarking/channels/load_test.exs \
  --concurrency 20 --duration 30

# Memory test with 1MB payloads
elixir --sname lt --cookie bench \
  benchmarking/channels/load_test.exs \
  --scenario large_payload --payload-size 1048576 --duration 30

# Ramp up to 50 VUs with CSV output
elixir --sname lt --cookie bench \
  benchmarking/channels/load_test.exs \
  --scenario ramp_up --concurrency 50 --duration 60 --csv results.csv

# Slow upstream latency test (start sink with: --mode delay --delay 2000)
elixir --sname lt --cookie bench \
  benchmarking/channels/load_test.exs \
  --scenario slow_sink --concurrency 10 --duration 30
```

## Interpreting Results

The load test prints a summary like:

```
═══════════════════════════════════════
 Channel Load Test Results
═══════════════════════════════════════
 Scenario:    happy_path
 Concurrency: 20 VUs
 Duration:    30s
───────────────────────────────────────
 Requests:    15432
 Throughput:  514.4 req/s
 Errors:      0 (0.0%)
───────────────────────────────────────
 Latency:
   p50:  12.3ms
   p95:  45.7ms
   p99:  89.2ms
───────────────────────────────────────
 Memory (Lightning BEAM):
   start:  128.5 MB
   end:    131.2 MB
   max:    135.0 MB
   delta:  +2.7 MB
═══════════════════════════════════════
```

### What "good" looks like

- **Memory delta** is the key metric for proxy correctness. If the proxy is
  streaming properly, memory should stay roughly flat regardless of payload
  size. A delta under **50 MB** for a 30-second test with 1MB payloads indicates
  correct streaming behaviour. A growing delta suggests the proxy is buffering
  entire request/response bodies in memory.

- **Throughput** depends heavily on your machine and the mock sink
  configuration. With a fast local sink and 20 VUs, expect 500+ req/s on modern
  hardware.

- **Latency p95** should be close to p50 for the `happy_path` scenario (no
  artificial delays). A large gap indicates contention or resource exhaustion.

- **Error rate** should be 0% for `happy_path` and `large_payload` scenarios.
  Non-zero errors suggest proxy bugs or resource limits.
