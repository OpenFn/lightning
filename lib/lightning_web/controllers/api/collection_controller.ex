defmodule LightningWeb.API.CollectionController do
  @moduledoc """
  Writes and reads a project's collection by id.
  `LightningWeb.CollectionsController` serves the items inside it.

      GET /api/projects/:project_id/collections/:id
      PUT /api/projects/:project_id/collections/:id  {"name": "patients"}

  Both answer `{"data": {"id", "project_id", "name"}}`.

      GET /api/projects/:project_id/collections
      GET /api/collections
      DELETE /api/projects/:project_id/collections/:id

  The lists are paged and take `sort`, and each collection in them carries
  `byte_size_sum`. Every project's list adds `project_name`.
  """
  use LightningWeb, :controller

  alias Lightning.Collections
  alias Lightning.Collections.Collection
  alias Lightning.Projects.Project
  alias LightningWeb.API.Errors
  alias LightningWeb.API.FallbackController
  alias LightningWeb.API.Filters
  alias LightningWeb.API.Request
  alias LightningWeb.API.Target
  alias LightningWeb.Plugs.AuthorizeAction

  action_fallback FallbackController

  plug AuthorizeAction,
       {:collections, :manage_collection}
       when action in [:show, :update, :index, :delete]

  plug AuthorizeAction,
       {:collections, :list_all_collections}
       when action == :list_all

  @accepted [:id, :name]
  @manage_collection {:collections, :manage_collection}

  @spec show(Plug.Conn.t(), map()) :: Plug.Conn.t() | {:error, term()}
  def show(conn, _params) do
    with {:ok, collection} <-
           Target.in_project(
             conn.assigns.scope,
             Request.param(conn, "project_id"),
             @manage_collection,
             Request.param(conn, "id"),
             &Collections.get_collection_for_project/2
           ) do
      render_collection(conn, collection)
    end
  end

  @doc """
  Creates the collection under the path's id in the project, or renames the
  project's collection that has it, keeping its items.

  An id held by another project's collection answers 409 `id_taken` to anyone
  permitted on the path's project, whether or not they can see the holder,
  since Lightning never moves a collection between projects. A refused body
  answers one 422 with its keys and the collection's fields together, before
  the plan limit is asked.
  """
  @spec update(Plug.Conn.t(), map()) :: Plug.Conn.t() | {:error, term()}
  def update(conn, _params) do
    body = conn.body_params

    with {:ok, project} <-
           Target.project(
             conn.assigns.scope,
             Request.param(conn, "project_id"),
             @manage_collection
           ),
         {:ok, id} <- Request.id(Request.param(conn, "id")),
         {:ok, target} <- update_target(id, project),
         {:ok, entries} <- Request.check(body, id, @accepted) do
      attrs = %{"name" => body["name"]}

      case target do
        :new -> create(conn, project, id, attrs, entries)
        collection -> rename(conn, collection, attrs, entries)
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
            do: update(conn, conn.params),
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

  @doc """
  A page of the project's collections, by `sort`.
  """
  @spec index(Plug.Conn.t(), map()) :: Plug.Conn.t() | {:error, term()}
  def index(conn, params) do
    with {:ok, project} <-
           Target.project(
             conn.assigns.scope,
             Request.param(conn, "project_id"),
             @manage_collection
           ),
         {:ok, order_by} <-
           params |> Filters.collection_sort() |> Errors.refuse_parameters() do
      page =
        Collections.paginate_project_collections(
          project,
          order_by,
          Filters.page(params)
        )

      render(conn, :index, page: page, filters: sort_filter(params))
    end
  end

  @doc """
  A page of every project's collections, by `sort`, for a superuser or the
  service account.
  """
  @spec list_all(Plug.Conn.t(), map()) :: Plug.Conn.t() | {:error, term()}
  def list_all(conn, params) do
    with {:ok, order_by} <-
           params |> Filters.collection_sort() |> Errors.refuse_parameters() do
      page = Collections.paginate_collections(order_by, Filters.page(params))
      render(conn, :index_all, page: page, filters: sort_filter(params))
    end
  end

  @doc """
  Deletes the project's collection and every item in it, recording the
  caller as having deleted it.
  """
  @spec delete(Plug.Conn.t(), map()) :: Plug.Conn.t() | {:error, term()}
  def delete(conn, _params) do
    with {:ok, collection} <-
           Target.in_project(
             conn.assigns.scope,
             Request.param(conn, "project_id"),
             @manage_collection,
             Request.param(conn, "id"),
             &Collections.get_collection_for_project/2
           ),
         {:ok, _deleted} <-
           Collections.delete_collection(
             collection,
             conn.assigns.current_resource
           ) do
      send_resp(conn, :no_content, "")
    end
  end

  # Reached only once `collection_sort/1` has accepted the sort.
  defp sort_filter(%{"sort" => sort}), do: %{sort: sort}
  defp sort_filter(_params), do: %{}
end
