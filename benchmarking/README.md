# Benchmarking

## Sample benchmarks

### System specs on a Thinkpad Carbon X1 5th Gen laptop

```
❯ sudo lshw -short
H/W path           Device          Class          Description
=============================================================
                                   system         20HR000HUS (LENOVO_MT_20HR_BU_Think_FM_ThinkPad X1 Carbon 5th)
/0                                 bus            20HR000HUS
/0/3                               memory         8GiB System Memory
/0/3/0                             memory         4GiB Row of chips LPDDR3 Synchronous Unbuffered (Unregistered) 1867 MHz (0.5 ns)
/0/3/1                             memory         4GiB Row of chips LPDDR3 Synchronous Unbuffered (Unregistered) 1867 MHz (0.5 ns)
/0/7                               memory         128KiB L1 cache
/0/8                               memory         512KiB L2 cache
/0/9                               memory         4MiB L3 cache
/0/a                               processor      Intel(R) Core(TM) i7-7600U CPU @ 2.80GHz
/0/b                               memory         128KiB BIOS
/0/100                             bridge         Xeon E3-1200 v6/7th Gen Core Processor Host Bridge/DRAM Registers
...
/0/100/1c.4/0      /dev/nvme0      storage        SAMSUNG MZVLW256HEHP-000L7
/0/100/1c.4/0/0    hwmon3          disk           NVMe disk
/0/100/1c.4/0/2    /dev/ng0n1      disk           NVMe disk
/0/100/1c.4/0/1    /dev/nvme0n1    disk           256GB NVMe disk
/0/100/1c.4/0/1/1  /dev/nvme0n1p1  volume         259MiB Windows FAT volume

❯ lsb_release -a
Description:	Ubuntu 22.04.3 LTS
Release:	22.04
```

### Results with 50kb payloads

```
❯ k6 run -e PAYLOAD_SIZE=50 benchmarking/script.js

          /\      |‾‾| /‾‾/   /‾‾/
     /\  /  \     |  |/  /   /  /
    /  \/    \    |     (   /   ‾‾\
   /          \   |  |\  \ |  (‾)  |
  / __________ \  |__| \__\ \_____/ .io

  execution: local
     script: benchmarking/script.js
     output: -

  scenarios: (100.00%) 1 scenario, 50 max VUs, 2m50s max duration (incl. graceful stop):
           * default: Up to 50 looping VUs for 2m20s over 3 stages (gracefulRampDown: 30s, gracefulStop: 30s)


     ✓ status was 200

     █ setup

     checks.........................: 100.00% ✓ 5271      ✗ 0
     data_received..................: 1.5 MB  11 kB/s
     data_sent......................: 265 MB  1.9 MB/s
     http_req_blocked...............: avg=11µs     min=1.92µs   med=4.72µs   max=7ms      p(90)=5.93µs   p(95)=7.09µs
     http_req_connecting............: avg=1.28µs   min=0s       med=0s       max=218.87µs p(90)=0s       p(95)=0s
   ✗ http_req_duration..............: avg=630.38ms min=44.61ms  med=612.48ms max=1.68s    p(90)=1.05s    p(95)=1.15s
       { expected_response:true }...: avg=630.38ms min=44.61ms  med=612.48ms max=1.68s    p(90)=1.05s    p(95)=1.15s
   ✓ http_req_failed................: 0.00%   ✓ 0         ✗ 5271
     http_req_receiving.............: avg=106.35µs min=21.5µs   med=61.35µs  max=26.63ms  p(90)=76.03µs  p(95)=88.56µs
     http_req_sending...............: avg=193.3µs  min=53.54µs  med=100.42µs max=20.72ms  p(90)=140.83µs p(95)=210.86µs
     http_req_tls_handshaking.......: avg=0s       min=0s       med=0s       max=0s       p(90)=0s       p(95)=0s
     http_req_waiting...............: avg=630.08ms min=44.47ms  med=612.17ms max=1.68s    p(90)=1.05s    p(95)=1.15s
     http_reqs......................: 5271    37.642872/s
     iteration_duration.............: avg=632.07ms min=180.16µs med=614.54ms max=1.69s    p(90)=1.05s    p(95)=1.15s
     iterations.....................: 5271    37.642872/s
     vus............................: 1       min=1       max=49
     vus_max........................: 50      min=50      max=50


running (2m20.0s), 00/50 VUs, 5271 complete and 0 interrupted iterations
default ✓ [======================================] 00/50 VUs  2m20s
ERRO[0141] thresholds on metrics 'http_req_duration' have been breached
```

## Run your own benchmarking tests

Execute the following steps to run a benchmark on Lightning:

1. Make sure you have [k6](https://k6.io/docs/get-started/installation/)
   installed locally. If you're using `asdf` you can run `asdf install` in the
   project root.

2. Start up a local Lightning instance with an attached iex session:

   `iex -S mix phx.server`

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

5. In another terminal (do not stop the Lightning server) run the
   `benchmarking/script.js` file using the following command

   ```bash
   k6 run benchmarking/script.js
   ```

   If the script exits successfully, this means the app met the defined
   performance thresholds.

   By default, the test payload is minimal. Should you wish to test it with
   larger payloads, you can pass in the `PAYLOAD_SIZE` ENV variable. This
   variable allows you to specify the payload size in KB (for now, integer
   values only), (e.g. 2000 KB):

   ```bash
   k6 run -e PAYLOAD_SIZE=2000 benchmarking/script.js
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
