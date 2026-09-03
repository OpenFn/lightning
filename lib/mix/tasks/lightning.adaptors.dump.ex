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

  alias Lightning.Adaptors.Catalogue

  @adaptor_fields ~w(name source description homepage repository license
                     latest_version deprecated schema_data schema_sha256
                     icon_square_ext icon_rectangle_ext
                     icon_square_sha256 icon_rectangle_sha256
                     icon_square_etag icon_rectangle_etag)a

  @version_fields ~w(version integrity tarball_url size_bytes dependencies
                     peer_dependencies published_at deprecated)a

  @icon_sha256_fields ~w(icon_square_sha256 icon_rectangle_sha256)a

  @impl Mix.Task
  def run(argv) do
    Mix.Task.run("app.start")

    {opts, _args} =
      OptionParser.parse!(argv, strict: [path: :string, source: :string])

    path =
      opts[:path] || raise "Usage: mix lightning.adaptors.dump --path <file>"

    source = parse_source(opts[:source])

    records =
      source
      |> Catalogue.list_adaptors()
      |> Enum.map(&dump_record(&1, source))

    File.write!(path, Jason.encode_to_iodata!(records))

    Mix.shell().info("Dumped #{length(records)} adaptor(s) to #{path}.")
  end

  # ponytail: one version query per adaptor; join them if a catalogue ever
  # grows past a few hundred rows.
  defp dump_record(adaptor, source) do
    versions =
      adaptor.name
      |> Catalogue.list_versions(source)
      |> Enum.map(&(&1 |> Map.from_struct() |> Map.take(@version_fields)))

    adaptor
    |> Map.from_struct()
    |> Map.take(@adaptor_fields)
    |> encode_icon_sha256s()
    |> Map.put(:versions, versions)
  end

  # icon_*_sha256 columns hold raw hash bytes, not valid JSON text; encode
  # them here, `Seed.normalize_snapshot_record/2` decodes on the way back in.
  defp encode_icon_sha256s(record) do
    Enum.reduce(@icon_sha256_fields, record, fn field, acc ->
      Map.update!(acc, field, &(&1 && Base.encode64(&1)))
    end)
  end

  defp parse_source(nil), do: :npm
  defp parse_source("npm"), do: :npm
  defp parse_source("local"), do: :local

  defp parse_source(other),
    do: raise("Unknown --source: #{other} (expected npm or local)")
end
