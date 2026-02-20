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

# Terminal 3 — Load test (single scenario)
elixir --sname loadtest --cookie bench \
  benchmarking/channels/load_test.exs \
  --scenario happy_path --concurrency 20 --duration 30

# Or run all scenarios in sequence:
benchmarking/channels/run_all.sh --duration 30 --concurrency 20
```

The load test will automatically create a "load-test" project and channel
pointing at the mock sink, then drive traffic through the proxy and report
results.

## File Structure

```
benchmarking/channels/
├── load_test.exs              # Entry point (~20 lines): Mix.install, loads modules, calls main()
├── mock_sink.exs              # Standalone mock HTTP sink server
├── run_all.sh                 # Runs all 7 scenarios in sequence
├── lib/
│   ├── load_test/
│   │   ├── config.exs         # LoadTest.Config — CLI parsing and validation
│   │   ├── metrics.exs        # LoadTest.Metrics — Agent-based latency/error collector
│   │   ├── setup.exs          # LoadTest.Setup — BEAM connection, channel creation, telemetry deploy
│   │   ├── runner.exs         # LoadTest.Runner — Scenario execution (steady, ramp-up, direct)
│   │   ├── report.exs         # LoadTest.Report — Results formatting and CSV output
│   │   └── main.exs           # LoadTest — Orchestrator (ties everything together)
│   └── telemetry_collector.exs # Bench.TelemetryCollector — Deployed to Lightning for server-side timing
└── results/
    └── .gitignore
```

The entry point (`load_test.exs`) installs deps via `Mix.install`, loads all
modules via `Code.require_file` in dependency order, then calls
`LoadTest.main(System.argv())`.

## Mock Sink (`mock_sink.exs`)

A standalone Bandit HTTP server that accepts all requests and responds according
to the configured mode.

```bash
elixir benchmarking/channels/mock_sink.exs [options]
```

### Options

| Option              | Default | Description                |
| ------------------- | ------- | -------------------------- |
| `--port PORT`       | 4001    | Listen port                |
| `--mode MODE`       | fixed   | Response mode (see below)  |
| `--status CODE`     | 200     | HTTP status for fixed mode |
| `--body-size BYTES` | 256     | Response body size         |

### Modes

| Mode        | Behaviour                                                                       |
| ----------- | ------------------------------------------------------------------------------- |
| **fixed**   | Returns `--status` with `--body-size` body (respects `?delay=N`)                |
| **timeout** | Accepts connection, never responds                                              |
| **auth**    | 401 if no `Authorization` header, 403 if invalid, 200 for `Bearer test-api-key` |
| **mixed**   | 80% fast 200, 10% slow 200 (2s delay), 10% 503                                  |

### Query Parameters

The mock sink supports per-request overrides via query parameters:

| Parameter          | Description                                     |
| ------------------ | ----------------------------------------------- |
| `?response_size=N` | Override `--body-size` for this request (bytes) |
| `?delay=N`         | Add a response delay for this request (ms)      |
| `?status=N`        | Override `--status` for this request (e.g. 503) |

This lets the load test control response sizes and delays without restarting the
sink:

```bash
# Default body size
curl http://localhost:4001/test

# Override to 5000 bytes for this request
curl "http://localhost:4001/test?response_size=5000"

# 500ms delay
curl "http://localhost:4001/test?delay=500"

# Combine both
curl "http://localhost:4001/test?delay=500&response_size=5000"
```

### Examples

```bash
# Default: fast 200 responses
elixir benchmarking/channels/mock_sink.exs

# Simulate flaky upstream
elixir benchmarking/channels/mock_sink.exs --mode mixed

# Large response bodies (5MB)
elixir benchmarking/channels/mock_sink.exs --body-size 5000000

# Require authentication
elixir benchmarking/channels/mock_sink.exs --mode auth

# Slow responses via query param (no restart needed)
curl "http://localhost:4001/test?delay=2000"
```

## Load Test (`load_test.exs`)

Drives HTTP traffic through the channel proxy, collects metrics, and reports
latency percentiles, throughput, error rates, BEAM memory usage, and server-side
telemetry timing breakdown.

```bash
elixir --sname loadtest --cookie COOKIE \
  benchmarking/channels/load_test.exs [options]
```

**Important:** Must be run as a named Erlang node (`--sname`) so it can connect
to the Lightning BEAM for channel setup, memory sampling, and telemetry.

### Options

| Option                  | Default                 | Description                                          |
| ----------------------- | ----------------------- | ---------------------------------------------------- |
| `--target URL`          | `http://localhost:4000` | Lightning base URL                                   |
| `--sink URL`            | `http://localhost:4001` | Mock sink URL (for channel creation)                 |
| `--node NODE`           | `lightning@hostname`    | Lightning node name                                  |
| `--cookie COOKIE`       | —                       | Erlang cookie (also settable via `elixir --cookie`)  |
| `--channel NAME`        | `load-test`             | Channel name to find/create                          |
| `--scenario NAME`       | `happy_path`            | Test scenario (see below)                            |
| `--concurrency N`       | 10                      | Concurrent virtual users                             |
| `--duration SECS`       | 30                      | Test duration                                        |
| `--payload-size BYTES`  | 1024                    | Request body size                                    |
| `--response-size BYTES` | —                       | Response body size override (via `?response_size=N`) |
| `--delay MS`            | — (slow_sink: 2000)     | Sink response delay (via `?delay=N`)                 |
| `--csv PATH`            | —                       | Optional CSV output file                             |

### Scenarios

| Scenario           | Description                                     | Mock sink mode        |
| ------------------ | ----------------------------------------------- | --------------------- |
| **happy_path**     | Sustained POST requests at constant concurrency | `fixed` (default)     |
| **ramp_up**        | Linearly ramp from 1 → N VUs over duration      | `fixed`               |
| **large_payload**  | POST with large request bodies (default 1MB)    | `fixed`               |
| **large_response** | GET requests with large response bodies         | `fixed --body-size N` |
| **mixed_methods**  | Rotate through GET, POST, PUT, PATCH, DELETE    | `fixed`               |
| **slow_sink**      | Measure latency with a slow upstream            | `fixed` + `?delay=N`  |
| **direct_sink**    | Hit mock sink directly (baseline measurement)   | `fixed` (default)     |

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

# Slow upstream latency test (delay applied via query param, no sink restart)
elixir --sname lt --cookie bench \
  benchmarking/channels/load_test.exs \
  --scenario slow_sink --delay 2000 --concurrency 10 --duration 30

# Baseline: hit mock sink directly (no Lightning needed, no --sname required)
elixir benchmarking/channels/load_test.exs \
  --scenario direct_sink --concurrency 20 --duration 10

# Large response test with explicit response size
elixir --sname lt --cookie bench \
  benchmarking/channels/load_test.exs \
  --scenario large_response --response-size 1048576 --duration 30
```

## Run All Scenarios (`run_all.sh`)

Runs all 7 scenarios in sequence, logging output to a timestamped file and
appending CSV rows for each scenario. Assumes Lightning and mock sink are
already running. Bails on first failure.

```bash
benchmarking/channels/run_all.sh [options]
```

### Options

| Option            | Default | Description           |
| ----------------- | ------- | --------------------- |
| `--sname NAME`    | lt      | Erlang short name     |
| `--cookie COOKIE` | bench   | Erlang cookie         |
| `--duration SECS` | 30      | Per-scenario duration |
| `--concurrency N` | 20      | Virtual users         |

### Scenario Order

| #   | Scenario         | Extra flags               |
| --- | ---------------- | ------------------------- |
| 1   | `direct_sink`    | (none — baseline)         |
| 2   | `happy_path`     | (none)                    |
| 3   | `ramp_up`        | (none)                    |
| 4   | `large_payload`  | `--payload-size 1048576`  |
| 5   | `large_response` | `--response-size 1048576` |
| 6   | `mixed_methods`  | (none)                    |
| 7   | `slow_sink`      | `--delay 2000`            |

### Examples

```bash
# Quick smoke test (10s per scenario, 5 VUs)
benchmarking/channels/run_all.sh --duration 10 --concurrency 5

# Full run with defaults (30s per scenario, 20 VUs)
benchmarking/channels/run_all.sh

# Custom node/cookie
benchmarking/channels/run_all.sh --sname mynode --cookie mysecret
```

Results are written to `/tmp/channel-bench-results/`:

- `YYYY.MM.DD-HH.MM.log` — full console output
- `YYYY.MM.DD-HH.MM.csv` — one row per scenario for analysis

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

### Telemetry Timing Breakdown

When running through Lightning (not `direct_sink`), the load test automatically
deploys a telemetry collector onto the Lightning BEAM node. After the test, it
prints a server-side timing breakdown:

```
───────────────────────────────────────
 Channel Proxy Timing (server-side):
     Total request      p50=12.3ms, p95=45.7ms, p99=89.2ms, n=15432
       DB lookup        p50=0.2ms,  p95=0.5ms,  p99=1.1ms,  n=15432
       Upstream proxy   p50=11.8ms, p95=44.9ms, p99=87.5ms, n=15432
```

This tells you exactly where time is spent inside the channel proxy:

| Metric             | What it measures                                                     |
| ------------------ | -------------------------------------------------------------------- |
| **Total request**  | Entire `ChannelProxyPlug.call/2` — DB lookup + proxy + plug overhead |
| **DB lookup**      | `Ecto.UUID.cast` + `Repo.get` to find the channel                    |
| **Upstream proxy** | `Weir.proxy` call — HTTP to the sink + response streaming back       |
| **Plug overhead**  | `Total request` - `DB lookup` - `Upstream proxy` = plug/header work  |

If `Total request` is much larger than `Upstream proxy`, the overhead is in the
Plug pipeline or DB lookup. If `Upstream proxy` dominates, the time is in the
network hop to the sink.

The telemetry collector uses ETS with `:public` access and `write_concurrency`
for minimal overhead — handlers run in the connection processes, not through a
GenServer bottleneck.

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

### Measuring proxy overhead with `direct_sink`

The `direct_sink` scenario hits the mock sink directly, bypassing Lightning
entirely. This gives a baseline for the test harness + mock sink latency:

```
proxy_overhead = happy_path_latency - direct_sink_latency
```

Run both and compare:

```bash
# Baseline (no Lightning needed)
elixir benchmarking/channels/load_test.exs \
  --scenario direct_sink --concurrency 20 --duration 10

# Through proxy
elixir --sname lt --cookie bench \
  benchmarking/channels/load_test.exs \
  --scenario happy_path --concurrency 20 --duration 10
```

The difference tells you exactly what the proxy pipeline (plugs, DB lookup,
Weir, second HTTP hop) costs per request. The telemetry breakdown further
decomposes that cost into DB lookup vs upstream proxy vs plug overhead.
