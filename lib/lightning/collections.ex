defmodule Lightning.Collections do
  @moduledoc """
  Access to collections of unique key-value pairs shared across multiple workflows.
  """
  import Ecto.Query

  alias Ecto.Multi

  alias Lightning.Collections.Collection
  alias Lightning.Collections.Item
  alias Lightning.Extensions.Message
  alias Lightning.Extensions.UsageLimiting.Action
  alias Lightning.Extensions.UsageLimiting.Context
  alias Lightning.Repo
  alias Lightning.Services.UsageLimiter

  @doc """
  Returns the list of collections with optional ordering and preloading.

  ## Parameters

    - `opts`: A keyword list of options.
      - `:order_by` (optional): The field by which to order the results. Default is `[asc: :name]`.
      - `:preload` (optional): A list of associations to preload. Default is `[:project]`.

  ## Examples

      iex> list_collections()
      [%Collection{}, ...]

      iex> list_collections(order_by: [asc: :inserted_at], preload: [:project, :user])
      [%Collection{}, ...]

  ## Returns

    - A list of `%Collection{}` structs, preloaded and ordered as specified.
  """
  @spec list_collections(keyword()) :: [Collection.t()]
  def list_collections(opts \\ []) do
    order_by = Keyword.get(opts, :order_by, asc: :name)
    preload = Keyword.get(opts, :preload, [:project])

    Repo.all(from(c in Collection, order_by: ^order_by, preload: ^preload))
  end

  @spec get_collection(String.t()) ::
          {:ok, Collection.t()} | {:error, :not_found}
  def get_collection(name) do
    case Repo.get_by(Collection, name: name) do
      nil -> {:error, :not_found}
      collection -> {:ok, collection}
    end
  end

  @doc """
  Creates a new collection with the given attributes.

  ## Parameters

    - `attrs`: A map of attributes to create the collection.

  ## Examples

      iex> create_collection(%{name: "New Collection", project_id: "a7895d29-02a9-42cd-845b-7ad893557c24"})
      {:ok, %Collection{}}

      iex> create_collection(%{name: nil, project_id: "a7895d29-02a9-42cd-845b-7ad893557c24"}})
      {:error, %Ecto.Changeset{}}

  ## Returns

    - `{:ok, %Collection{}}` on success.
    - `{:error, %Ecto.Changeset{}}` on failure due to validation errors.
  """
  @spec create_collection(map()) ::
          {:ok, Collection.t()}
          | {:error, Ecto.Changeset.t()}
          | {:error, :exceeds_limit, Message.t()}
  def create_collection(%{"project_id" => project_id} = attrs) do
    Multi.new()
    |> Multi.run(:limiter, fn _repo, _changes ->
      case UsageLimiter.limit_action(%Action{type: :collection_create}, %Context{
             project_id: project_id
           }) do
        :ok -> {:ok, nil}
        {:error, :exceeds_limit, message} -> {:error, message}
      end
    end)
    |> Multi.insert(:create, Collection.changeset(%Collection{}, attrs))
    |> Repo.transaction()
    |> case do
      {:ok, %{create: collection}} -> {:ok, collection}
      {:error, :limiter, message, _changes} -> {:error, :exceeds_limit, message}
      {:error, _op, changeset, _changes} -> {:error, changeset}
    end
  end

  @doc """
  Updates an existing collection with the given attributes.

  ## Parameters

    - `collection`: The existing `%Collection{}` struct to update.
    - `attrs`: A map of attributes to update the collection.

  ## Examples

      iex> update_collection(collection, %{name: "Updated Name"})
      {:ok, %Collection{}}

      iex> update_collection(collection, %{name: nil})
      {:error, %Ecto.Changeset{}}

  ## Returns

    - `{:ok, %Collection{}}` on success.
    - `{:error, %Ecto.Changeset{}}` on failure due to validation errors.
  """
  @spec update_collection(Collection.t(), map()) ::
          {:ok, Collection.t()} | {:error, Ecto.Changeset.t()}
  def update_collection(collection, attrs) do
    collection
    |> Collection.changeset(attrs)
    |> Repo.update()
  end

  @spec delete_collection(Ecto.UUID.t()) ::
          {:ok, Collection.t()}
          | {:error, Ecto.Changeset.t()}
          | {:error, :not_found}
  def delete_collection(collection_id) do
    case Repo.get(Collection, collection_id) do
      nil -> {:error, :not_found}
      collection -> Repo.delete(collection)
    end
  end

  @spec get(Collection.t(), String.t()) :: Item.t() | nil
  def get(%{id: collection_id}, key) do
    Repo.get_by(Item, collection_id: collection_id, key: key)
  end

  @spec get_all(Collection.t(), Enum.t(), String.t() | nil) :: Enum.t()
  def get_all(%{id: collection_id}, params, key_pattern \\ nil) do
    params = Map.new(params)
    cursor = Map.get(params, :cursor)
    limit = Map.fetch!(params, :limit)

    collection_id
    |> all_query(cursor, limit)
    |> filter_by_inserted_at(params)
    |> filter_by_updated_at(params)
    |> then(fn query ->
      if key_pattern do
        where(query, [i], like(i.key, ^format_pattern(key_pattern)))
      else
        query
      end
    end)
    |> Repo.all()
  end

  @spec put(Collection.t(), String.t(), String.t()) ::
          :ok | {:error, Ecto.Changeset.t()}
  def put(collection, key, value) do
    case get(collection, key) do
      nil ->
        upsert_item(collection, %Item{collection_id: collection.id}, key, value)

      item ->
        upsert_item(collection, item, key, value)
    end
  end

  @spec put_all(Collection.t(), [{String.t(), String.t()}]) ::
          {:ok, non_neg_integer()}
          | {:error, :duplicate_key}
          | {:error, :exceeds_limit, Message.t()}
  def put_all(%{id: collection_id, project_id: project_id}, kv_list) do
    now = DateTime.utc_now()

    {item_list, {key_list, new_mem_used}} =
      Enum.map_reduce(kv_list, {[], 0}, fn %{"key" => key, "value" => value},
                                           {key_list, mem_used} ->
        {
          %{
            collection_id: collection_id,
            key: key,
            value: value,
            inserted_at: now,
            updated_at: now
          },
          {
            [key | key_list],
            mem_used + byte_size(key) + byte_size(value)
          }
        }
      end)

    Multi.new()
    |> Multi.one(
      :old_mem_used,
      from(c in Item,
        where: c.collection_id == ^collection_id and c.key in ^key_list,
        select: fragment("sum(octet_length(key) + octet_length(value))::bigint")
      )
    )
    |> Multi.run(:increment_size, fn _repo, %{old_mem_used: old_mem_used} ->
      {:ok, new_mem_used - (old_mem_used || 0)}
    end)
    |> Multi.run(:limiter, fn _repo, %{increment_size: increment_size} ->
      case limit_put(project_id, increment_size) do
        :ok -> {:ok, nil}
        {:error, :exceeds_limit, message} -> {:error, message}
      end
    end)
    |> Multi.insert_all(:items, Item, item_list,
      conflict_target: [:collection_id, :key],
      on_conflict: {:replace, [:value, :updated_at]}
    )
    |> Multi.update_all(
      :collection,
      fn %{increment_size: increment_size} ->
        increment = [byte_size_sum: increment_size]

        from(c in Collection,
          where: c.id == ^collection_id,
          update: [inc: ^increment]
        )
      end,
      []
    )
    |> Repo.transaction()
    |> case do
      {:ok, %{items: {count, nil}}} -> {:ok, count}
      {:error, :limiter, message, _changes} -> {:error, :exceeds_limit, message}
      {:error, _op, changeset, _changes} -> {:error, changeset}
    end
  rescue
    e in Postgrex.Error ->
      if e.postgres.code == :cardinality_violation do
        {:error, :duplicate_key}
      else
        reraise e, __STACKTRACE__
      end
  end

  @spec delete(Collection.t(), String.t()) :: :ok | {:error, :not_found}
  def delete(collection, key) do
    case get(collection, key) do
      nil -> {:error, :not_found}
      item -> delete_item(item)
    end
  end

  @spec delete_all(Collection.t(), String.t() | nil) :: {:ok, non_neg_integer()}
  def delete_all(%{id: collection_id}, key_pattern \\ nil) do
    query =
      from(i in Item, where: i.collection_id == ^collection_id)
      |> then(fn query ->
        case key_pattern do
          nil -> query
          pattern -> where(query, [i], like(i.key, ^format_pattern(pattern)))
        end
      end)

    with {count, _nil} <- Repo.delete_all(query), do: {:ok, count}
  end

  defp upsert_item(
         %Collection{project_id: project_id},
         %Item{value: old_value} = item,
         key,
         value
       ) do
    Multi.new()
    |> Multi.run(:increment_size, fn _repo, _changes ->
      if is_nil(old_value) do
        {:ok, byte_size(key) + byte_size(value)}
      else
        {:ok, byte_size(value) - byte_size(old_value)}
      end
    end)
    |> Multi.run(:limiter, fn _repo, %{increment_size: increment_size} ->
      with :ok <- limit_put(project_id, increment_size), do: {:ok, nil}
    end)
    |> Multi.insert(
      :item,
      fn _no_change ->
        Item.changeset(item, %{
          key: key,
          value: value
        })
      end,
      conflict_target: [:collection_id, :key],
      on_conflict: [
        set: [value: value, updated_at: DateTime.utc_now()]
      ]
    )
    |> Multi.update_all(
      :collection,
      fn %{item: %{collection_id: collection_id}, increment_size: increment_size} ->
        from(c in Collection,
          where: c.id == ^collection_id,
          update: [inc: ^[byte_size_sum: increment_size]]
        )
      end,
      []
    )
    |> Repo.transaction()
    |> case do
      {:ok, _changes} -> :ok
      {:error, _op, changeset, _changes} -> {:error, changeset}
    end
  end

  defp delete_item(%{collection_id: collection_id, key: key, value: value}) do
    Multi.new()
    |> Multi.delete_all(:item, fn _no_change ->
      from(i in Item, where: i.collection_id == ^collection_id and i.key == ^key)
    end)
    |> Multi.update_all(
      :collection,
      fn _changes ->
        increment = [byte_size_sum: -(byte_size(key) + byte_size(value))]

        from(c in Collection,
          where: c.id == ^collection_id,
          update: [inc: ^increment]
        )
      end,
      []
    )
    |> Repo.transaction()
    |> case do
      {:ok, %{item: {1, nil}}} -> :ok
      {:ok, %{item: {0, nil}}} -> {:error, :not_found}
      {:error, _op, changeset, _changes} -> {:error, changeset}
    end
  end

  defp all_query(collection_id, cursor, limit) do
    Item
    |> where([i], i.collection_id == ^collection_id)
    |> order_by([i], asc: i.id)
    |> limit(^limit)
    |> then(fn query ->
      case cursor do
        nil -> query
        ts_cursor -> where(query, [i], i.id > ^ts_cursor)
      end
    end)
  end

  defp filter_by_inserted_at(query, params) do
    query
    |> filter_by_created_before(params)
    |> filter_by_created_after(params)
  end

  defp filter_by_updated_at(query, params) do
    query
    |> filter_by_updated_before(params)
    |> filter_by_updated_after(params)
  end

  defp filter_by_created_after(query, %{created_after: created_after}),
    do: where(query, [i], i.inserted_at >= ^created_after)

  defp filter_by_created_after(query, _params), do: query

  defp filter_by_created_before(query, %{created_before: created_before}),
    do: where(query, [i], i.inserted_at < ^created_before)

  defp filter_by_created_before(query, _params), do: query

  defp filter_by_updated_after(query, %{updated_after: updated_after}),
    do: where(query, [i], i.updated_at >= ^updated_after)

  defp filter_by_updated_after(query, _params), do: query

  defp filter_by_updated_before(query, %{updated_before: updated_before}),
    do: where(query, [i], i.updated_at < ^updated_before)

  defp filter_by_updated_before(query, _params), do: query

  defp format_pattern(pattern) do
    pattern
    |> String.replace("\\", "\\\\")
    |> String.replace("%", "\\%")
    |> String.replace("*", "%")
  end

  defp limit_put(project_id, requested_size) do
    UsageLimiter.limit_action(
      %Action{type: :collection_put, amount: requested_size},
      %Context{project_id: project_id}
    )
  end
end
