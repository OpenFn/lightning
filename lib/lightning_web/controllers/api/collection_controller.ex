defmodule LightningWeb.API.CollectionController do
  @moduledoc """
  Writes and reads a project's collection by id.
  `LightningWeb.CollectionsController` serves the items inside it.

      GET /api/projects/:project_id/collections/:id
      PUT /api/projects/:project_id/collections/:id  {"name": "patients"}

  Both answer `{"data": {"id", "project_id", "name"}}`.
  """
  use LightningWeb, :controller

  alias Lightning.Collections
  alias Lightning.Collections.Collection
  alias Lightning.Projects.Project
  alias LightningWeb.API.Errors
  alias LightningWeb.API.FallbackController
  alias LightningWeb.API.Request
  alias LightningWeb.API.Target
  alias LightningWeb.Plugs.AuthorizeAction

  action_fallback FallbackController

  plug AuthorizeAction,
       {:collections, :manage_collection}
       when action in [:show, :update]

  @accepted [:id, :name]
  @manage_collection {:collections, :manage_collection}

  @spec show(Plug.Conn.t(), map()) :: Plug.Conn.t() | {:error, term()}
  def show(conn, %{"project_id" => project_id, "id" => id}) do
    with {:ok, collection} <-
           Target.in_project(
             conn.assigns.scope,
             project_id,
             @manage_collection,
             &fetch_collection(id, &1)
           ) do
      render_collection(conn, collection)
    end
  end

  @doc """
  Creates the collection under the path's id in the project, or renames the
  project's collection that has it, keeping its items.

  An id held by another project's collection answers 409 `id_taken`, since
  Lightning never moves a collection between projects. A refused body answers
  one 422 with its keys and the collection's fields together, before the plan
  limit is asked (error-format spec §4, D13).
  """
  @spec update(Plug.Conn.t(), map()) :: Plug.Conn.t() | {:error, term()}
  def update(conn, %{"project_id" => project_id, "id" => id}) do
    body = conn.body_params

    with {:ok, project} <-
           Target.project(conn.assigns.scope, project_id, @manage_collection),
         {:ok, id} <- Request.path_id(id),
         {:ok, target} <- update_target(id, project),
         {:ok, entries} <- Request.check(body, id, @accepted) do
      attrs = %{"name" => body["name"]}

      case target do
        :new -> create(conn, project, id, attrs, entries)
        collection -> rename(conn, collection, attrs, entries)
      end
    end
  end

  defp fetch_collection(id, %Project{id: project_id}) do
    with {:ok, id} <- Request.path_id(id) do
      case Collections.get_collection_by_id(id) do
        %Collection{project_id: ^project_id} = collection -> {:ok, collection}
        _ -> {:error, :not_found}
      end
    end
  end

  defp update_target(id, %Project{id: project_id}) do
    case Collections.get_collection_by_id(id) do
      nil -> {:ok, :new}
      %Collection{project_id: ^project_id} = collection -> {:ok, collection}
      %Collection{} -> {:error, :id_taken}
    end
  end

  defp create(conn, project, id, attrs, entries) do
    attrs = Map.put(attrs, "project_id", project.id)

    changeset = Collection.changeset(%Collection{id: id}, attrs)

    with :ok <- Errors.refuse(entries ++ Errors.from_changeset(changeset)) do
      case Collections.create_collection(
             attrs,
             conn.assigns.current_resource,
             id: id
           ) do
        {:ok, collection} ->
          conn |> put_status(:created) |> render_collection(collection)

        # Someone else created it since the lookup. Rerun the request so it
        # meets that collection.
        {:error, %Ecto.Changeset{} = changeset} ->
          if Request.id_taken?(changeset),
            do: update(conn, %{"project_id" => project.id, "id" => id}),
            else: {:error, changeset}

        error ->
          error
      end
    end
  end

  defp rename(conn, collection, attrs, entries) do
    changeset = Collection.rename_changeset(collection, attrs)

    with :ok <- Errors.refuse(entries ++ Errors.from_changeset(changeset)),
         {:ok, collection} <-
           Collections.update_collection(
             collection,
             attrs,
             conn.assigns.current_resource
           ) do
      render_collection(conn, collection)
    end
  end

  defp render_collection(conn, collection) do
    json(conn, %{data: Map.take(collection, [:id, :project_id, :name])})
  end
end
