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

  @spec stream_all(Collection.t(), Keyword.t()) :: Enum.t()
  def stream_all(%{id: collection_id}, opts \\ []) do
    cursor = Keyword.get(opts, :cursor)
    limit = Keyword.fetch!(opts, :limit)

    collection_id
    |> stream_query(cursor, limit)
    |> Repo.stream()
  end

  @spec stream_match(Collection.t(), String.t(), Keyword.t()) :: Enum.t()
  def stream_match(
        %{id: collection_id},
        pattern,
        opts \\ []
      ) do
    pattern = format_pattern(pattern)
    cursor = Keyword.get(opts, :cursor)
    limit = Keyword.fetch!(opts, :limit)

    collection_id
    |> stream_query(cursor, limit)
    |> where([i], like(i.key, ^pattern))
    |> Repo.stream()
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
          {:ok, non_neg_integer()} | :error
  def put_all(%{id: collection_id}, kv_list) do
    item_list =
      Enum.with_index(kv_list, fn %{"key" => key, "value" => value},
                                  unique_index ->
        now = DateTime.add(DateTime.utc_now(), unique_index, :microsecond)

        %{
          collection_id: collection_id,
          key: key,
          value: value,
          inserted_at: now,
          updated_at: now
        }
      end)

    case Repo.insert_all(Item, item_list,
           conflict_target: [:collection_id, :key],
           on_conflict: {:replace, [:value, :updated_at]}
         ) do
      {n, nil} when n > 0 -> {:ok, n}
      _error -> :error
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

  @spec delete_all(Collection.t(), String.t()) :: {:ok, non_neg_integer()} | {:error, :not_found}
  def delete_all(%{id: collection_id}, key_pattern \\ nil) do
    query =
      from(i in Item, where: i.collection_id == ^collection_id)
      |> then(fn query ->
        case key_pattern do
          nil -> query
          pattern -> where(query, [i], like(i.key, ^format_pattern(pattern)))
        end
      end)


    case Repo.delete_all(query) do
      {0, nil} -> {:error, :not_found}
      {n, nil} -> {:ok, n}
    end
  end

  defp stream_query(collection_id, cursor, limit) do
    Item
    |> where([i], i.collection_id == ^collection_id)
    |> order_by([i], asc: i.updated_at)
    |> limit(^limit)
    |> then(fn query ->
      case cursor do
        nil -> query
        ts_cursor -> where(query, [i], i.updated_at > ^ts_cursor)
      end
    end)
  end

  defp format_pattern(pattern) do
    pattern
    |> String.replace("\\", "\\\\")
    |> String.replace("%", "\\%")
    |> String.replace("*", "%")
  end
end
