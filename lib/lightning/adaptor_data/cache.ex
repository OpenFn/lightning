defmodule Lightning.AdaptorData.Cache do
  @moduledoc """
  Cachex-backed read-through cache for adaptor data.

  Read path: Cachex -> DB -> nil
  Write path: DB -> broadcast invalidate -> all nodes clear Cachex
  Next read on any node: cache miss -> DB hit -> Cachex populated
  """

  @cache :adaptor_data

  @doc "Get a cached value. Falls back to DB on miss, populates cache."
  def get(kind, key) do
    case Cachex.get!(@cache, {kind, key}) do
      nil ->
        case Lightning.AdaptorData.get(kind, key) do
          {:error, :not_found} ->
            nil

          {:ok, entry} ->
            value = %{data: entry.data, content_type: entry.content_type}
            Cachex.put!(@cache, {kind, key}, value)
            value
        end

      value ->
        value
    end
  end

  @doc "Get all entries of a kind. Falls back to DB on miss."
  def get_all(kind) do
    case Cachex.get!(@cache, {kind, :__all__}) do
      nil ->
        case Lightning.AdaptorData.get_all(kind) do
          [] ->
            []

          entries ->
            values =
              Enum.map(entries, fn e ->
                %{key: e.key, data: e.data, content_type: e.content_type}
              end)

            Cachex.put!(@cache, {kind, :__all__}, values)
            values
        end

      cached ->
        cached
    end
  end

  @doc "Put a value directly into the cache (does not touch the DB)."
  def put(kind, key, value) do
    Cachex.put!(@cache, {kind, key}, value)
    :ok
  end

  @doc "Invalidate all cached entries for a kind."
  def invalidate(kind) do
    @cache
    |> Cachex.keys!()
    |> Enum.filter(&match?({^kind, _}, &1))
    |> Enum.each(&Cachex.del!(@cache, &1))

    :ok
  end

  @doc "Invalidate all cached entries."
  def invalidate_all do
    Cachex.clear!(@cache)
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
