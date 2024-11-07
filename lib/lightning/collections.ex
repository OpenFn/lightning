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

  @spec get_collection(String.t()) ::
          {:ok, Collection.t()} | {:error, :collection_not_found}
  def get_collection(name) do
    case Repo.get_by(Collection, name: name) do
      nil -> {:error, :collection_not_found}
      collection -> {:ok, collection}
    end
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

  @spec delete(Collection.t(), String.t()) :: :ok | {:error, :not_found}
  def delete(%{id: collection_id}, key) do
    query =
      from(i in Item, where: i.collection_id == ^collection_id and i.key == ^key)

    case Repo.delete_all(query) do
      {0, nil} -> {:error, :not_found}
      {1, nil} -> :ok
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
        cursor_key -> where(query, [i], i.key > ^cursor_key)
      end
    end)
  end
end
