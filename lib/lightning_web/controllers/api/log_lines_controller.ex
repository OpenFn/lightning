defmodule LightningWeb.API.LogLinesController do
  @moduledoc """
  API controller for managing log lines.

  ## Query Parameters

  - `page` - Page number (default: 1)
  - `page_size` - Number of items per page (default: 10, at most 100)
  - `timestamp_after` - Filter logs after this ISO8601 datetime
  - `timestamp_before` - Filter logs before this ISO8601 datetime
  - `project_id` - The project the lines come from, which the caller must be
    able to access
  - `workflow_id` - Filter by workflow UUID
  - `job_id` - Filter by job UUID
  - `work_order_id` - Filter by work order UUID
  - `run_id` - Filter by run UUID
  - `level` - Filter by log level (success, always, info, warn, error, debug)

  The service account must send `project_id` on the list, as these tables grow
  with every run; leaving it out is 400 `invalid_parameter`.

  ## Examples

      GET /api/log_lines?page=1&page_size=50
      GET /api/log_lines?timestamp_after=2024-01-01T00:00:00Z
      GET /api/log_lines?run_id=uuid&level=error
      GET /api/log_lines?project_id=uuid&timestamp_after=2024-01-01T00:00:00Z

  """
  use LightningWeb, :controller

  alias Lightning.Invocation
  alias LightningWeb.API.Errors
  alias LightningWeb.API.FallbackController
  alias LightningWeb.API.Filters
  alias LightningWeb.API.Request
  alias LightningWeb.API.Target

  action_fallback FallbackController

  plug LightningWeb.Plugs.AuthorizeAction,
       {:project_users, :access_project}

  @doc """
  Lists the log lines of the projects the caller may access, or of the one
  project `project_id` names, narrowed by the query's filters.

  The caller is authorised on `project_id` before the query is read, so a
  caller who may not see the project learns nothing from its filters. Every
  bad filter is reported in one 400 `invalid_parameter`.
  """
  @spec index(Plug.Conn.t(), map()) :: Plug.Conn.t() | {:error, term()}
  def index(conn, %{"project_id" => _} = params) do
    with {:ok, project} <-
           Target.project(
             conn.assigns.scope,
             Request.param(conn, "project_id"),
             {:project_users, :access_project}
           ),
         {:ok, filters} <-
           params
           |> Filters.log_lines(conn.assigns.scope)
           |> Errors.refuse_parameters() do
      list(project, conn, params, filters, %{project_id: project.id})
    end
  end

  def index(conn, params) do
    with {:ok, filters} <-
           params
           |> Filters.log_lines(conn.assigns.scope)
           |> Errors.refuse_parameters() do
      list(conn.assigns.scope, conn, params, filters, %{})
    end
  end

  defp list(project_or_scope, conn, params, filters, target) do
    page =
      Invocation.paginate_log_lines_for(
        project_or_scope,
        filters,
        Filters.page(params)
      )

    render(conn, "index.json",
      page: page,
      filters: Map.merge(filters, target),
      conn: conn
    )
  end
end
