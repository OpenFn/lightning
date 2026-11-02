defmodule LightningWeb.API.HistoryExportController do
  @moduledoc """
  A project's history exports: zips of work orders, with their inputs, outputs
  and logs, that Lightning builds in the background
  (`Lightning.WorkOrders.ExportWorker`).

  Asking for one needs a role that may run the project's workflows; listing,
  reading and downloading them is open to any member. All are for people only.
  """
  use LightningWeb, :controller

  alias Lightning.Invocation
  alias Lightning.Projects
  alias Lightning.Storage.ProjectFileDefinition
  alias LightningWeb.API.FallbackController
  alias LightningWeb.API.Filters
  alias LightningWeb.API.HistoryBody
  alias LightningWeb.API.Request
  alias LightningWeb.API.Target

  action_fallback FallbackController

  plug LightningWeb.Plugs.AuthorizeAction,
       {:history, :run_workflow}
       when action == :create

  plug LightningWeb.Plugs.AuthorizeAction,
       {:history, :read_history}
       when action in [:index, :show, :download]

  @doc """
  Asks for an export of the work orders `filter` matches, the list endpoint's
  filters, or of every work order when the body sends none. Answers 202 with
  the export, `enqueued`; Lightning emails the person when it is ready. A
  project deleted after the lookup read it is 409 `concurrent_edit`.

  ## Examples

      POST /api/projects/a1b2c3d4-.../history_exports
      {"filter": {"state": "failed", "inserted_after": "2026-01-01T00:00:00Z"}}
  """
  @spec create(Plug.Conn.t(), map()) :: Plug.Conn.t() | {:error, term()}
  def create(conn, _params) do
    scope = conn.assigns.scope
    user = conn.assigns.current_resource

    with {:ok, project} <-
           Target.project(
             scope,
             Request.param(conn, "project_id"),
             {:history, :run_workflow}
           ),
         {:ok, selection, _extra} <-
           HistoryBody.selection(conn.body_params, scope, [],
             ids: false,
             required: false
           ),
         {:ok, export} <- export(project, user, selection.search) do
      conn
      |> put_status(:accepted)
      |> render("show.json", export: export, conn: conn)
    end
  end

  # A project deleted after the lookup read it.
  defp export(project, user, search) do
    case Invocation.export_workorders(project, user, search) do
      {:ok, %{project_file: export}} ->
        {:ok, export}

      {:error, :project_file, %Ecto.Changeset{errors: [project_id: _]}, _} ->
        {:error, :concurrent_edit}
    end
  end

  @doc """
  Lists the project's exports, newest first, a page at a time.

  ## Examples

      GET /api/projects/a1b2c3d4-.../history_exports?page=2
  """
  @spec index(Plug.Conn.t(), map()) :: Plug.Conn.t() | {:error, term()}
  def index(conn, params) do
    with {:ok, project} <-
           Target.project(
             conn.assigns.scope,
             Request.param(conn, "project_id"),
             {:history, :read_history}
           ) do
      page = Projects.paginate_project_files(project, Filters.page(params))
      render(conn, "index.json", page: page, conn: conn)
    end
  end

  @doc """
  Shows one of the project's exports.

  ## Examples

      GET /api/projects/a1b2c3d4-.../history_exports/e5f6a7b8-...
  """
  @spec show(Plug.Conn.t(), map()) :: Plug.Conn.t() | {:error, term()}
  def show(conn, _params) do
    with {:ok, export} <- fetch(conn) do
      render(conn, "show.json", export: export, conn: conn)
    end
  end

  @doc """
  Sends a completed export's zip, or redirects to it in cloud storage. An
  export that isn't completed has no file yet, and is 404 `not_found`.

  ## Examples

      GET /api/projects/a1b2c3d4-.../history_exports/e5f6a7b8-.../download
  """
  # sobelow_skip ["Traversal.SendDownload"]
  # The path is made by storage_path_for_exports/2 from Lightning's own UUIDs.
  @spec download(Plug.Conn.t(), map()) :: Plug.Conn.t() | {:error, term()}
  def download(conn, _params) do
    with {:ok, %{status: :completed} = export} <- fetch(conn),
         {:ok, file_url} <- ProjectFileDefinition.get_url(export) do
      case URI.parse(file_url) do
        %{scheme: "file", path: path} -> send_download(conn, {:file, path})
        _cloud_url -> redirect(conn, external: file_url)
      end
    else
      {:ok, _not_completed} -> {:error, :not_found}
      refused -> refused
    end
  end

  defp fetch(conn) do
    Target.in_project(
      conn.assigns.scope,
      Request.param(conn, "project_id"),
      {:history, :read_history},
      Request.param(conn, "id"),
      &Projects.get_project_file_for_project/2
    )
  end
end
