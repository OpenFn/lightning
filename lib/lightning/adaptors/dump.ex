defmodule Lightning.Adaptors.Dump do
  @moduledoc """
  Writes the adaptor catalogue to a JSON snapshot file, in the shape
  `Lightning.Adaptors.Seed.seed_from_file/2` reads back.
  """

  alias Lightning.Adaptors.Catalogue

  @adaptor_fields ~w(name source description homepage repository license
                     latest_version deprecated schema_data schema_sha256
                     icon_square_ext icon_rectangle_ext
                     icon_square_sha256 icon_rectangle_sha256
                     icon_square_etag icon_rectangle_etag)a

  @version_fields ~w(version integrity tarball_url size_bytes dependencies
                     peer_dependencies published_at deprecated)a

  @icon_sha256_fields ~w(icon_square_sha256 icon_rectangle_sha256)a

  @doc """
  Writes every `source` adaptor and its versions to `path` as JSON, and
  returns the number of records written.

  Options:

    * `:source` - `:npm` (default) or `:local`
  """
  @spec dump_to_file(Path.t(), keyword()) :: {:ok, non_neg_integer()}
  def dump_to_file(path, opts \\ []) do
    source = Keyword.get(opts, :source, :npm)

    records =
      source
      |> Catalogue.list_adaptors()
      |> Enum.map(&dump_record(&1, source))

    File.write!(path, Jason.encode_to_iodata!(records))

    {:ok, length(records)}
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

  # icon_*_sha256 columns hold raw hash bytes, not valid JSON text;
  # `Lightning.Adaptors.Seed.normalize_snapshot_record/2` decodes on the
  # way back in.
  defp encode_icon_sha256s(record) do
    Enum.reduce(@icon_sha256_fields, record, fn field, acc ->
      Map.update!(acc, field, &(&1 && Base.encode64(&1)))
    end)
  end
end
