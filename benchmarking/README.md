# Benchmarking

Execute the following steps to run a benchmark on Lightning:

1. Make sure you have [k6](https://k6.io/docs/get-started/installation/)
   installed locally. If you're using `asdf` you can run `asdf install` in the
   project root.

2. Start up a local Lightning instance with an attached iex session:
    
    `iex -S mix phx.server`

3. In the attached iex session, run the following, to have Lightning log internal telemetry data:

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

    If the script exits successfully, this means the app met the defined performance
    thresholds.

    By default, the test payload is minimal. Should you wish to test it with larger payloads,
    you can pass in the `PAYLOAD_SIZE` ENV variable. This variable allows you to specify the payload
    size in KB (for now, integer values only), (e.g. 2000 KB):

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
