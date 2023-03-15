# Benchmarking

Execute the following steps to run a benchmark on Lightning:

1. Make sure you have [k6](https://k6.io/docs/get-started/installation/)
   installed locally. If you're using `asdf` you can run `asdf install` in the
   project root.

2. Spin up your Lightning local instance

3. Run the demo setup script: `mix run --no-start priv/repo/demo.exs` The
   `webhookURL` is already set to default to the webhook created in the demo
   data

4. In another terminal (do not stop the Lightning server) run the
   `benchmarking/script.js` file using the following command

```bash
k6 run benchmarking/script.js
```

If the script exits succesfully, this means the app met the defined performance
thresholds.

To collect the benchmarking data in a CSV file, run the previous command with
the `--out filename` option.

```bash
k6 run --out csv=test_results.csv benchmarking/script.js
```

See [results output](https://k6.io/docs/get-started/results-output/) for other
available output formats.
