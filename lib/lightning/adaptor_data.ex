defmodule Lightning.AdaptorData do
  @moduledoc """
  Context for managing adaptor cache entries in the database.

  Provides CRUD operations for storing adaptor registry data, credential
  schemas, adaptor icons, and other cacheable adaptor metadata. Each entry
  is keyed by a `kind` (category) and a unique `key` within that kind.
  """
  import Ecto.Query

  alias Lightning.AdaptorData.CacheEntry
  alias Lightning.Repo

  @doc """
  Upserts a single cache entry.

  If an entry with the same `kind` and `key` already exists, its `data`,
  `content_type`, and `updated_at` fields are replaced.

  Returns `{:ok, %CacheEntry{}}` or `{:error, %Ecto.Changeset{}}`.
  """
  @spec put(String.t(), String.t(), binary(), String.t()) ::
          {:ok, CacheEntry.t()} | {:error, Ecto.Changeset.t()}
  def put(kind, key, data, content_type \\ "application/json") do
    %CacheEntry{}
    |> CacheEntry.changeset(%{
      kind: kind,
      key: key,
      data: data,
      content_type: content_type
    })
    |> Repo.insert(
      conflict_target: [:kind, :key],
      on_conflict: {:replace, [:data, :content_type, :updated_at]},
      returning: true
    )
  end

  @doc """
  Bulk upserts a list of entries for the given `kind`.

  Each entry in `entries` must be a map with `:key`, `:data`, and optionally
  `:content_type` keys.

  Returns `{count, nil | [%CacheEntry{}]}` where `count` is the number of
  rows affected.
  """
  @spec put_many(String.t(), [map()]) :: {non_neg_integer(), nil}
  def put_many(kind, entries) when is_list(entries) do
    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

    rows =
      Enum.map(entries, fn entry ->
        %{
          id: Ecto.UUID.generate(),
          kind: kind,
          key: Map.fetch!(entry, :key),
          data: Map.fetch!(entry, :data),
          content_type: Map.get(entry, :content_type, "application/json"),
          inserted_at: now,
          updated_at: now
        }
      end)

    Repo.insert_all(CacheEntry, rows,
      conflict_target: [:kind, :key],
      on_conflict: {:replace, [:data, :content_type, :updated_at]}
    )
  end

  @doc """
  Gets a single cache entry by `kind` and `key`.

  Returns `{:ok, %CacheEntry{}}` or `{:error, :not_found}`.
  """
  @spec get(String.t(), String.t()) ::
          {:ok, CacheEntry.t()} | {:error, :not_found}
  def get(kind, key) do
    case Repo.get_by(CacheEntry, kind: kind, key: key) do
      nil -> {:error, :not_found}
      entry -> {:ok, entry}
    end
  end

  @doc """
  Gets all cache entries for the given `kind`.

  Returns a list of `%CacheEntry{}` structs ordered by key.
  """
  @spec get_all(String.t()) :: [CacheEntry.t()]
  def get_all(kind) do
    CacheEntry
    |> where([e], e.kind == ^kind)
    |> order_by([e], asc: e.key)
    |> Repo.all()
  end

  @doc """
  Deletes all cache entries for the given `kind`.

  Returns `{count, nil}` where `count` is the number of deleted rows.
  """
  @spec delete_kind(String.t()) :: {non_neg_integer(), nil}
  def delete_kind(kind) do
    CacheEntry
    |> where([e], e.kind == ^kind)
    |> Repo.delete_all()
  end

  @doc """
  Deletes a specific cache entry by `kind` and `key`.

  Returns `{:ok, %CacheEntry{}}` or `{:error, :not_found}`.
  """
  @spec delete(String.t(), String.t()) ::
          {:ok, CacheEntry.t()} | {:error, :not_found}
  def delete(kind, key) do
    case Repo.get_by(CacheEntry, kind: kind, key: key) do
      nil -> {:error, :not_found}
      entry -> {:ok, Repo.delete!(entry)}
    end
  end
end
