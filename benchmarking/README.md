# Benchmarking

## Run benchmarking tests against the demo webhook

Execute the following steps to run a benchmark on Lightning:

1. Make sure you have [k6](https://k6.io/docs/get-started/installation/)
   installed locally. If you're using `asdf` you can run `asdf install` in the
   project root.

2. Start up a local Lightning instance with an attached iex session. Note that
   to simulate a production environment, set `RTM=false`. In prod, you'll have
   your `ws-worker` running on a separate machine:

   `RMT=false iex -S mix phx.server`

3. In the attached iex session, run the following, to have Lightning log
   internal telemetry data:

   ```elixir
     filepath = Path.join("benchmarking", "load_test_data.csv")
     output_file = File.open!(filepath, [:append])

     c "benchmarking/load_test_production_spans.exs"

     LoadTestingPrep.init(output_file)
   ```

4. Run the demo setup script: `mix run --no-start priv/repo/demo.exs` The
   `webhookURL` is already set to default to the webhook created in the demo
   data

   If you would like to point at a different instance or webhook url you
   can provide it via `WEBHOOK_URL`.

5. In another terminal (do not stop the Lightning server) run the
   `benchmarking/script.js` file using the following command

   ```bash
   k6 run benchmarking/script.js
   ```

   If the script exits successfully, this means the app met the defined
   performance thresholds.

   By default, the test payload is just 2 kb. Should you wish to test it with
   larger payloads, you can pass in the `PAYLOAD_SIZE_KB` ENV variable. This
   variable allows you to specify the payload size in KB (for now, integer
   values only), (e.g. 2 KB):

   ```bash
   k6 run -e PAYLOAD_SIZE_KB=2 benchmarking/script.js
   ```

   To collect the benchmarking data in a CSV file, run the previous command with
   the `--out filename` option.

   ```bash
   k6 run --out csv=test_results.csv benchmarking/script.js
   ```

6. In the iex session, close the output file:

   ```elixir
   LoadTestingPrep.fin(output_file)
   ```

See [results output](https://k6.io/docs/get-started/results-output/) for other
available output formats.

### Sample benchmarks

#### System specs on a 2020 MacBook Pro

```
Model Name: MacBook Pro
Model Identifier: MacBookPro17,1
Model Number: Z11B000E3LL/A
Chip: Apple M1
Total Number of Cores: 8 (4 performance and 4 efficiency)
Memory: 16 GB
```

#### Results with 50kb payloads

```
k6 run -e PAYLOAD_SIZE=10 benchmarking/script.js                         Node 18.17.1 k6 0.43.1 07:40:29

          /\      |‾‾| /‾‾/   /‾‾/
     /\  /  \     |  |/  /   /  /
    /  \/    \    |     (   /   ‾‾\
   /          \   |  |\  \ |  (‾)  |
  / __________ \  |__| \__\ \_____/ .io

  execution: local
     script: benchmarking/script.js
     output: -

  scenarios: (100.00%) 1 scenario, 50 max VUs, 2m50s max duration (incl. graceful stop):
           * webhookRequests: Up to 50.00 iterations/s for 2m20s over 3 stages (maxVUs: 50, gracefulStop: 30s)


     ✓ status was 200

     █ setup

     checks.........................: 100.00% ✓ 5765     ✗ 0
     data_received..................: 1.6 MB  12 kB/s
     data_sent......................: 59 MB   421 kB/s
     http_req_blocked...............: avg=16.01µs min=2µs     med=9µs     max=6.84ms   p(90)=12µs    p(95)=13µs
     http_req_connecting............: avg=4.35µs  min=0s      med=0s      max=2.22ms   p(90)=0s      p(95)=0s
   ✓ http_req_duration..............: avg=53.62ms min=26.86ms med=49.03ms max=501.62ms p(90)=66.62ms p(95)=84.33ms
       { expected_response:true }...: avg=53.62ms min=26.86ms med=49.03ms max=501.62ms p(90)=66.62ms p(95)=84.33ms
   ✓ http_req_failed................: 0.00%   ✓ 0        ✗ 5765
     http_req_receiving.............: avg=88.57µs min=13µs    med=90µs    max=2.99ms   p(90)=108µs   p(95)=124.8µs
     http_req_sending...............: avg=97.47µs min=29µs    med=83µs    max=6.86ms   p(90)=139µs   p(95)=162µs
     http_req_tls_handshaking.......: avg=0s      min=0s      med=0s      max=0s       p(90)=0s      p(95)=0s
     http_req_waiting...............: avg=53.44ms min=26.68ms med=48.84ms max=501.43ms p(90)=66.43ms p(95)=84.05ms
     http_reqs......................: 5765    41.15402/s
     iteration_duration.............: avg=54.34ms min=20.75µs med=49.75ms max=502.26ms p(90)=67.39ms p(95)=84.91ms
     iterations.....................: 5765    41.15402/s
     vus............................: 50      min=50     max=50
     vus_max........................: 50      min=50     max=50


running (2m20.1s), 00/50 VUs, 5765 complete and 0 interrupted iterations
webhookRequests ✓ [======================================] 00/50 VUs  2m20s  01.12 iters/s
```

## Run load tests for a hypothetical cold chain system

`benchmarking/sample_cold_chain_monitoring_script.js` contains a k6 script that
can be used to simulate data from a hypothetical cold chain system. It requires a
custom job to be created (an example of which can be found at the top of the
script file).

The test can be excuted as follows (`WEBHOOK_URL` is not optional):

```bash
   WEBHOOK_URL=... k6 run benchmarking/sample_cold_chain_monitoring_script.js
```
