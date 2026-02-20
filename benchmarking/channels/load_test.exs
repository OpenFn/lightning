# benchmarking/channels/load_test.exs
#
# Entry point for the channel proxy load test. Installs dependencies,
# loads all modules in dependency order, and runs the test.
#
# Usage:
#   elixir --sname loadtest --cookie SECRET \
#     benchmarking/channels/load_test.exs [options]
#
# Run with --help for full usage information.

Mix.install([:finch, :jason])

base = Path.dirname(__ENV__.file)

for file <- ~w(config metrics setup runner report main) do
  Code.require_file("lib/load_test/#{file}.exs", base)
end

Code.require_file("lib/telemetry_collector.exs", base)

LoadTest.main(System.argv())
