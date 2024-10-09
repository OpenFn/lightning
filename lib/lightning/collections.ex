defmodule Lightning.Collections do
  @moduledoc """
  Access to collections of unique key-value pairs shared across multiple workflows.
  """
  alias Lightning.Collections.Collection
  alias Lightning.Collections.Item
  alias Lightning.Repo

  @spec create_collection(Ecto.UUID.t(), String.t()) ::
          {:ok, Collection.t()} | {:error, Ecto.Changeset.t()}
  def create_collection(project_id, name) do
    %Collection{}
    |> Collection.changeset(%{project_id: project_id, name: name})
    |> Repo.insert()
  end

  @spec delete_collection(Ecto.UUID.t()) ::
          {:ok, Collection.t()} | {:error, Ecto.Changeset.t()}
  def delete_collection(collection_id) do
    case Repo.get(Collection, collection_id) do
      nil -> {:error, :collection_not_found}
      collection -> Repo.delete(collection)
    end
  end

  @spec get(String.t(), String.t()) ::
          {:ok, Item.t()}
          | {:error, :not_found}
          | {:error, :collection_not_found}
  def get(col_name, key) do
    with {:col, %{id: collection_id}} <-
           {:col, Repo.get_by(Collection, name: col_name)},
         {:item, %Item{} = item} <-
           {:item, Repo.get_by(Item, collection_id: collection_id, key: key)} do
      {:ok, item}
    else
      {:col, nil} ->
        {:error, :collection_not_found}

      {:item, nil} ->
        {:error, :not_found}
    end
  end

  @spec put(String.t(), String.t(), String.t()) ::
          :ok | {:error, :collection_not_found}
  def put(col_name, key, value) do
    case Repo.get_by(Collection, name: col_name) do
      nil ->
        {:error, :collection_not_found}

      collection ->
        with nil <- Repo.get_by(Item, collection_id: collection.id, key: key) do
          %Item{}
        end
        |> Item.changeset(%{collection_id: collection.id, key: key, value: value})
        |> Repo.insert_or_update()
    end
  end

  @spec delete(String.t(), String.t()) ::
          {:ok, Item.t()}
          | {:error, :not_found}
          | {:error, :collection_not_found}
  def delete(col_name, key) do
    case Repo.get_by(Collection, name: col_name) do
      nil ->
        {:error, :collection_not_found}

      collection ->
        case Repo.get_by(Item, collection_id: collection.id, key: key) do
          nil -> {:error, :not_found}
          item -> Repo.delete(item)
        end
    end
  end
end
