defmodule Mix.Tasks.Lightning.SeedAdaptorsFromFile do
  @shortdoc "Seed the adaptor catalogue from a local JSON snapshot"

  @moduledoc """
  Populate the `adaptors` table from a JSON file, without reaching npm.

  The file is a JSON array of adaptor records in the shape
  `Lightning.Adaptors.Repo.upsert_adaptor/1` accepts — the same shape
  `mix lightning.download_adaptor_registry_cache` writes.

  ## Usage

      mix lightning.seed_adaptors_from_file --path snapshot.json
      mix lightning.seed_adaptors_from_file --path snapshot.json --source local
      mix lightning.seed_adaptors_from_file --path snapshot.json --replace

  `--source` defaults to `npm`. `--replace` deletes every existing row for
  that source first, so the file becomes the source's entire contents
  rather than a merge.

  ## In a release

  There is no Mix (or this task) in a release image. Seed from a
  snapshot before starting the app by running the equivalent through
  `bin/lightning eval` instead:

      bin/lightning eval 'Lightning.Release.seed_adaptors("/path/to/snapshot.json", replace: true)'
  """

  use Mix.Task

  alias Lightning.Adaptors

  @impl Mix.Task
  def run(argv) do
    Mix.Task.run("app.start")

    {opts, _args} =
      OptionParser.parse!(argv,
        strict: [path: :string, source: :string, replace: :boolean]
      )

    path =
      opts[:path] ||
        raise "Usage: mix lightning.seed_adaptors_from_file --path <file>"

    source = parse_source(opts[:source])

    {:ok, count} =
      Adaptors.seed_from_file(path,
        source: source,
        replace: opts[:replace] || false
      )

    Mix.shell().info("Seeded #{count} adaptor(s) from #{path}.")
  end

  defp parse_source(nil), do: :npm
  defp parse_source("npm"), do: :npm
  defp parse_source("local"), do: :local

  defp parse_source(other),
    do: raise("Unknown --source: #{other} (expected npm or local)")
end
