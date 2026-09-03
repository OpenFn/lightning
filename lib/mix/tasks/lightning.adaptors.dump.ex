defmodule Mix.Tasks.Lightning.Adaptors.Dump do
  @shortdoc "Dump the adaptor catalogue to a JSON snapshot file"

  @moduledoc """
  Write this instance's adaptor catalogue to a JSON file, in the shape
  `Lightning.Adaptors.Catalogue.upsert_adaptor/1` accepts — the shape
  `mix lightning.adaptors.import` reads back.

  This is the catalogue-to-file leg of mirroring adaptors into an
  airgapped environment: hydrate an online instance as usual, dump it
  here, carry the file across, and import it on the offline instance.
  `mix lightning.adaptors.snapshot` produces the same kind of file by
  fetching npm directly, for when there is no populated catalogue to
  dump from.

  ## Usage

      mix lightning.adaptors.dump --path snapshot.json
      mix lightning.adaptors.dump --path snapshot.json --source local

  `--source` defaults to `npm`.

  Icon bytes themselves live in the on-disk icon cache, not the catalogue,
  so they don't travel in this file. It carries the icon metadata
  (extension, sha256, etag) so an imported row can serve an icon already
  present at `ADAPTORS_ICONS_PATH` on the target instance instead of
  refetching from GitHub; copy that directory across alongside this file.
  """

  use Mix.Task

  alias Lightning.Adaptors

  @impl Mix.Task
  def run(argv) do
    Mix.Task.run("app.start")

    {opts, _args} =
      OptionParser.parse!(argv, strict: [path: :string, source: :string])

    path =
      opts[:path] || raise "Usage: mix lightning.adaptors.dump --path <file>"

    source = parse_source(opts[:source])

    {:ok, count} = Adaptors.dump_to_file(path, source: source)

    Mix.shell().info("Dumped #{count} adaptor(s) to #{path}.")
  end

  defp parse_source(nil), do: :npm
  defp parse_source("npm"), do: :npm
  defp parse_source("local"), do: :local

  defp parse_source(other),
    do: raise("Unknown --source: #{other} (expected npm or local)")
end
