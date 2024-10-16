defmodule Lightning.Collections do
  @moduledoc """
  Access to collections of unique key-value pairs shared across multiple workflows.
  """
  import Ecto.Query

  alias Lightning.Collections.Collection
  alias Lightning.Collections.Item
  alias Lightning.Repo

  @query_all_limit Application.compile_env!(:lightning, __MODULE__)[
                     :query_all_limit
                   ]

  @doc """
  Returns the list of collections with optional ordering and preloading.

  ## Examples

      iex> list_collections()
      [%Collection{}, ...]

      iex> list_collections(order_by: [asc: :inserted_at], preload: [:project, :user])
      [%Collection{}, ...]

  """
  @spec list_collections(keyword()) :: [Collection.t()]
  def list_collections(opts \\ []) do
    order_by = Keyword.get(opts, :order_by, asc: :name)
    preload = Keyword.get(opts, :preload, [:project])

    Repo.all(from(c in Collection, order_by: ^order_by, preload: ^preload))
  end

  @spec get_collection(String.t()) ::
          {:ok, Collection.t()} | {:error, :collection_not_found}
  def get_collection(name) do
    case Repo.get_by(Collection, name: name) do
      nil -> {:error, :collection_not_found}
      collection -> {:ok, collection}
    end
  end

  def create_collection(attrs) do
    %Collection{}
    |> Collection.changeset(attrs)
    |> Repo.insert()
  end

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
          | {:error, :collection_not_found}
  def delete_collection(collection_id) do
    case Repo.get(Collection, collection_id) do
      nil -> {:error, :collection_not_found}
      collection -> Repo.delete(collection)
    end
  end

  @spec get(Collection.t(), String.t()) :: Item.t()
  def get(%{id: collection_id}, key) do
    Repo.get_by(Item, collection_id: collection_id, key: key)
  end

  @spec stream_all(Collection.t(), String.t() | nil, integer()) :: Enum.t()
  def stream_all(%{id: collection_id}, cursor \\ nil, limit \\ @query_all_limit) do
    collection_id
    |> stream_query(cursor, limit)
    |> Repo.stream()
  end

  @spec stream_match(Collection.t(), String.t(), String.t() | nil, integer()) ::
          Enum.t()
  def stream_match(
        %{id: collection_id},
        pattern,
        cursor \\ nil,
        limit \\ @query_all_limit
      ) do
    pattern =
      pattern
      |> String.replace("\\", "\\\\")
      |> String.replace("%", "\\%")
      |> String.replace("*", "%")

    collection_id
    |> stream_query(cursor, limit)
    |> where([i], like(i.key, ^pattern))
    |> Repo.stream()
  end

  @spec put(Collection.t(), String.t(), String.t()) ::
          {:ok, Item.t()} | {:error, Ecto.Changeset.t()}
  def put(%{id: collection_id}, key, value) do
    with nil <- Repo.get_by(Item, collection_id: collection_id, key: key) do
      %Item{}
    end
    |> Item.changeset(%{collection_id: collection_id, key: key, value: value})
    |> Repo.insert_or_update()
  end

  @spec delete(Collection.t(), String.t()) ::
          {:ok, Item.t()} | {:error, :not_found}
  def delete(%{id: collection_id}, key) do
    case Repo.get_by(Item, collection_id: collection_id, key: key) do
      nil -> {:error, :not_found}
      item -> Repo.delete(item)
    end
  end

  defp stream_query(collection_id, cursor, limit) do
    Item
    |> where([i], i.collection_id == ^collection_id)
    |> limit(^limit)
    |> then(fn query ->
      case cursor do
        nil -> query
        cursor_key -> where(query, [i], i.key > ^cursor_key)
      end
    end)
  end
end
