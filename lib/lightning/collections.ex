defmodule Lightning.Collections do
  @moduledoc """
  Access to collections of unique key-value pairs shared across multiple workflows.
  """
  import Ecto.Query

  alias Lightning.Collections.Collection
  alias Lightning.Collections.Item
  alias Lightning.Repo

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

  @spec get_all(Collection.t()) :: Enum.t()
  def get_all(%{id: collection_id}) do
    query_all = from(i in Item, where: i.collection_id == ^collection_id)

    Repo.stream(query_all)
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
end
