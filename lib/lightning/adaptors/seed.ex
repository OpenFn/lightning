defmodule Lightning.Adaptors.Seed do
  @moduledoc """
  Populates the adaptor catalogue from a JSON snapshot file.
  """

  alias Lightning.Adaptors.Catalogue

  @doc """
  Populates the catalogue from a JSON snapshot file and returns the
  number of records written.

  The file is a JSON array of adaptor records in the shape
  `Lightning.Adaptors.Catalogue.upsert_adaptor/1` accepts, as written by
  `mix lightning.download_adaptor_registry_cache`.

  Options:

    * `:source` - `:npm` (default) or `:local`
    * `:replace` - when `true`, deletes every existing row for the source
      first, in the same transaction as the upserts
  """
  @spec seed_from_file(Path.t(), keyword()) :: {:ok, non_neg_integer()}
  def seed_from_file(path, opts \\ []) do
    source = Keyword.get(opts, :source, :npm)
    replace? = Keyword.get(opts, :replace, false)

    records =
      path
      |> File.read!()
      |> Jason.decode!()
      |> Enum.map(&normalize_snapshot_record(&1, source))

    {:ok, _} =
      Lightning.Repo.transaction(fn ->
        if replace?, do: Catalogue.delete_all_for_source(source)
        Enum.each(records, &Catalogue.upsert_adaptor/1)
      end)

    {:ok, length(records)}
  end

  # `dependencies` and `peer_dependencies` keep string keys; that is how
  # the `:map` columns store them.
  defp normalize_snapshot_record(record, source) when is_map(record) do
    record
    |> atomize_known_keys()
    |> Map.put(:source, source)
    |> Map.update(:versions, [], fn versions ->
      Enum.map(versions, &atomize_known_keys/1)
    end)
  end

  defp atomize_known_keys(map) do
    Map.new(map, fn {k, v} -> {String.to_existing_atom(k), v} end)
  end
end
