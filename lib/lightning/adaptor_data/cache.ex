defmodule Lightning.AdaptorData.Cache do
  @moduledoc """
  ETS-backed read-through cache for adaptor data.

  Read path: ETS -> DB -> nil
  Write path: DB -> broadcast invalidate -> all nodes clear ETS
  Next read on any node: ETS miss -> DB hit -> ETS populated
  """

  @table __MODULE__

  @doc "Create the ETS table. Called from Application.start/2."
  def init do
    if :ets.whereis(@table) == :undefined do
      :ets.new(@table, [
        :set,
        :public,
        :named_table,
        read_concurrency: true
      ])
    end

    :ok
  end

  @doc "Get a cached value. Falls back to DB on miss, populates ETS."
  def get(kind, key) do
    cache_key = {kind, key}

    case :ets.lookup(@table, cache_key) do
      [{^cache_key, value}] ->
        value

      [] ->
        case Lightning.AdaptorData.get(kind, key) do
          {:error, :not_found} ->
            nil

          {:ok, entry} ->
            value = %{data: entry.data, content_type: entry.content_type}
            :ets.insert(@table, {cache_key, value})
            value
        end
    end
  end

  @doc "Get all entries of a kind. Falls back to DB on miss."
  def get_all(kind) do
    cache_key = {kind, :__all__}

    case :ets.lookup(@table, cache_key) do
      [{^cache_key, entries}] ->
        entries

      [] ->
        entries = Lightning.AdaptorData.get_all(kind)

        if entries != [] do
          values =
            Enum.map(entries, fn e ->
              %{key: e.key, data: e.data, content_type: e.content_type}
            end)

          :ets.insert(@table, {cache_key, values})
          values
        else
          []
        end
    end
  end

  @doc "Invalidate all cached entries for a kind."
  def invalidate(kind) do
    # Delete the :__all__ key
    :ets.delete(@table, {kind, :__all__})

    # Delete individual keys for this kind
    :ets.select_delete(@table, [
      {{{kind, :_}, :_}, [], [true]}
    ])

    :ok
  end

  @doc "Invalidate all cached entries."
  def invalidate_all do
    :ets.delete_all_objects(@table)
    :ok
  end

  @doc "Broadcast cache invalidation to all nodes."
  def broadcast_invalidation(kinds) when is_list(kinds) do
    Lightning.API.broadcast(
      "adaptor:data",
      {:invalidate_cache, kinds, node()}
    )
  end
end
