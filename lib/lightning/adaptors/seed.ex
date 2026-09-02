defmodule Lightning.Adaptors.Seed do
  @moduledoc """
  Populates the adaptor catalogue from a JSON snapshot file.
  """

  alias Lightning.Adaptors.Catalogue
  alias Lightning.Adaptors.Supervisor, as: AdaptorsSupervisor

  @doc """
  Populates the catalogue from a JSON snapshot file and returns the
  number of records written.

  The file is a JSON array of adaptor records in the shape
  `Lightning.Adaptors.Catalogue.upsert_adaptor/1` accepts, as written by
  `mix lightning.adaptors.snapshot` or `mix lightning.adaptors.dump`.

  Once the transaction commits, broadcasts `{:changed, name, source}` for
  every name the seed touched, so each node's
  `Lightning.Adaptors.Invalidator` drops its now-stale cache entries. In
  `replace: true` mode that includes names the wipe removed.

  Options:

    * `:source` - `:npm` (default) or `:local`
    * `:replace` - when `true`, deletes every existing row for the source
      first, in the same transaction as the upserts
    * `:sup` - supervisor instance whose topic the broadcasts go to,
      defaulting to `Lightning.Adaptors`
  """
  @spec seed_from_file(Path.t(), keyword()) :: {:ok, non_neg_integer()}
  def seed_from_file(path, opts \\ []) do
    source = Keyword.get(opts, :source, :npm)
    replace? = Keyword.get(opts, :replace, false)
    sup = Keyword.get(opts, :sup, Lightning.Adaptors)

    records =
      path
      |> File.read!()
      |> Jason.decode!()
      |> Enum.map(&normalize_snapshot_record(&1, source))

    replaced_names =
      if replace?,
        do: Enum.map(Catalogue.list_adaptors(source), & &1.name),
        else: []

    {:ok, _} =
      Lightning.Repo.transaction(fn ->
        if replace?, do: Catalogue.delete_all_for_source(source)
        Enum.each(records, &Catalogue.upsert_adaptor/1)
      end)

    broadcast_changed(
      sup,
      source,
      Enum.uniq(Enum.map(records, & &1["name"]) ++ replaced_names)
    )

    {:ok, length(records)}
  end

  # `Lightning.Release.seed_adaptors/2` seeds through
  # `Ecto.Migrator.with_repo/2`, which starts the repo without the rest of
  # the app — there is no PubSub to broadcast on, and no cache to evict.
  defp broadcast_changed(sup, source, names) do
    if Process.whereis(Lightning.PubSub) do
      topic = AdaptorsSupervisor.source_topic(sup)

      Enum.each(names, fn name ->
        Phoenix.PubSub.broadcast(
          Lightning.PubSub,
          topic,
          {:changed, name, source}
        )
      end)
    end
  end

  @icon_sha256_fields ~w(icon_square_sha256 icon_rectangle_sha256)

  defp normalize_snapshot_record(record, source) when is_map(record) do
    record
    |> Map.put("source", source)
    |> decode_icon_sha256s()
  end

  # Reverses `Mix.Tasks.Lightning.Adaptors.Dump`'s base64 encoding of the
  # raw hash bytes those columns hold; a plain-npm snapshot has no such keys.
  defp decode_icon_sha256s(record) do
    Enum.reduce(@icon_sha256_fields, record, fn field, acc ->
      case Map.get(acc, field) do
        nil -> acc
        encoded -> Map.put(acc, field, Base.decode64!(encoded))
      end
    end)
  end
end
