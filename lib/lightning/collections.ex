defmodule Lightning.Collections do
  @moduledoc """
  Access to collections of unique key-value pairs shared across multiple workflows.
  """
  import Ecto.Query

  alias Lightning.Collections.Collection
  alias Lightning.Collections.Item
  alias Lightning.Repo

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

      iex> create_collection(%{name: "New Collection", description: "Description here"})
      {:ok, %Collection{}}

      iex> create_collection(%{name: nil})
      {:error, %Ecto.Changeset{}}

  ## Returns

    - `{:ok, %Collection{}}` on success.
    - `{:error, %Ecto.Changeset{}}` on failure due to validation errors.
  """
  @spec create_collection(map()) ::
          {:ok, Collection.t()} | {:error, Ecto.Changeset.t()}
  def create_collection(attrs) do
    %Collection{}
    |> Collection.changeset(attrs)
    |> Repo.insert()
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

  @spec create_collection(Ecto.UUID.t(), String.t()) ::
          {:ok, Collection.t()} | {:error, Ecto.Changeset.t()}
  def create_collection(project_id, name) do
    %Collection{}
    |> Collection.changeset(%{project_id: project_id, name: name})
    |> Repo.insert()
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
  def put(%{id: collection_id}, key, value) do
    %Item{}
    |> Item.changeset(%{collection_id: collection_id, key: key, value: value})
    |> Repo.insert(
      conflict_target: [:collection_id, :key],
      on_conflict: [set: [value: value, updated_at: DateTime.utc_now()]]
    )
    |> then(fn result ->
      with {:ok, _no_return} <- result, do: :ok
    end)
  end

  @spec put_all(Collection.t(), [{String.t(), String.t()}]) ::
          {:ok, non_neg_integer()} | {:error, :duplicate_key}
  def put_all(%{id: collection_id}, kv_list) do
    now = DateTime.utc_now()

    item_list =
      Enum.map(kv_list, fn %{"key" => key, "value" => value} ->
        %{
          collection_id: collection_id,
          key: key,
          value: value,
          inserted_at: now,
          updated_at: now
        }
      end)

    with {count, _nil} <-
           Repo.insert_all(Item, item_list,
             conflict_target: [:collection_id, :key],
             on_conflict: {:replace, [:value, :updated_at]}
           ),
         do: {:ok, count}
  rescue
    e in Postgrex.Error ->
      if e.postgres.code == :cardinality_violation do
        {:error, :duplicate_key}
      else
        reraise e, __STACKTRACE__
      end
  end

  @spec delete(Collection.t(), String.t()) :: :ok | {:error, :not_found}
  def delete(%{id: collection_id}, key) do
    query =
      from(i in Item, where: i.collection_id == ^collection_id and i.key == ^key)

    case Repo.delete_all(query) do
      {0, nil} -> {:error, :not_found}
      {1, nil} -> :ok
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
end
