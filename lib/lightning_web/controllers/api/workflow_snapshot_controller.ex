defmodule LightningWeb.API.WorkflowSnapshotController do
  @moduledoc """
  A workflow's snapshots: every save that changes a workflow keeps one,
  numbered by `lock_version`, and a run records the one it ran.

  Open to a person on either of their tokens who can access the workflow's
  project; the service account and repo connections are refused 403. The
  parent of `/api/workflows/:id` is the instance, and only the service account
  learns which workflows exist, so to a person an unknown or malformed workflow
  id is 403 `forbidden`, like one in a project they can't access. Once the
  workflow is theirs to read, a snapshot it hasn't got is 404 and a malformed
  snapshot id 400.

  ## Examples

      GET /api/workflows/a1b2c3d4-.../snapshots?page=2
      GET /api/workflows/a1b2c3d4-.../snapshots/e5f6a7b8-...
  """
  use LightningWeb, :controller

  alias Lightning.Workflows
  alias Lightning.Workflows.Snapshot
  alias LightningWeb.API.Filters
  alias LightningWeb.API.Request
  alias LightningWeb.API.Target
  alias LightningWeb.Plugs.AuthorizeAction

  action_fallback LightningWeb.API.FallbackController

  @read {:workflows, :read_workflow_history}

  plug AuthorizeAction, @read

  @doc """
  A page of the workflow's snapshots, newest first, each with `latest` set on
  the one matching the workflow's current `lock_version`.
  """
  @spec index(Plug.Conn.t(), map()) :: Plug.Conn.t() | {:error, term()}
  def index(conn, params) do
    with {:ok, workflow} <- fetch_workflow(conn) do
      page = Snapshot.paginate_for(workflow, Filters.page(params))

      render(conn, "index.json",
        page: page,
        workflow: workflow,
        conn: conn
      )
    end
  end

  @doc """
  One snapshot, as the workflow object as it was, with its `lock_version`.
  """
  @spec show(Plug.Conn.t(), map()) :: Plug.Conn.t() | {:error, term()}
  def show(conn, _params) do
    with {:ok, workflow} <- fetch_workflow(conn),
         {:ok, snapshot_id} <- Request.id(Request.param(conn, "snapshot_id")),
         {:ok, snapshot} <- Snapshot.get_for_workflow(workflow.id, snapshot_id) do
      render(conn, "show.json", snapshot: snapshot, workflow: workflow)
    end
  end

  defp fetch_workflow(conn) do
    Target.in_project_of(
      conn.assigns.scope,
      Request.param(conn, "id"),
      @read,
      &Workflows.get_project_id/1,
      &Workflows.get_workflow_for_project/2
    )
  end
end
