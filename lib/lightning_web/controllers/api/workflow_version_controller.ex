defmodule LightningWeb.API.WorkflowVersionController do
  @moduledoc """
  A workflow's versions: each save records a hash of the workflow and where
  the save came from, `app` or `cli`, so a CLI can tell whether the app and
  its local copy have moved apart.

  Open to a person on either of their tokens who can access the workflow's
  project; the service account and repo connections are refused 403. To a
  person an unknown or malformed workflow id is 403 `forbidden`, as for a
  workflow in a project they can't access.

  ## Examples

      GET /api/workflows/a1b2c3d4-.../versions?page=2
  """
  use LightningWeb, :controller

  alias Lightning.Workflows
  alias Lightning.WorkflowVersions
  alias LightningWeb.API.Filters
  alias LightningWeb.API.Request
  alias LightningWeb.API.Target
  alias LightningWeb.Plugs.AuthorizeAction

  action_fallback LightningWeb.API.FallbackController

  @read {:workflows, :read_workflow_history}

  plug AuthorizeAction, @read

  @doc "A page of the workflow's versions, newest first."
  @spec index(Plug.Conn.t(), map()) :: Plug.Conn.t() | {:error, term()}
  def index(conn, params) do
    with {:ok, workflow} <-
           Target.in_project_of(
             conn.assigns.scope,
             Request.param(conn, "id"),
             @read,
             &Workflows.get_project_id/1,
             &Workflows.get_workflow_for_project/2
           ) do
      page = WorkflowVersions.paginate_for(workflow, Filters.page(params))
      render(conn, "index.json", page: page, conn: conn)
    end
  end
end
