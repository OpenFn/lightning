defmodule LightningWeb.API.RunController do
  @moduledoc """
  API controller for managing runs.

  ## Query Parameters

  - `page` - Page number (default: 1)
  - `page_size` - Number of items per page (default: 10, at most 100)
  - `state` - Filter by state (comma-separated). Valid values: available, claimed, started, success, failed, crashed, cancelled, killed, exception, lost
  - `inserted_after` - Filter runs created after this ISO8601 datetime
  - `inserted_before` - Filter runs created before this ISO8601 datetime
  - `updated_after` - Filter runs updated after this ISO8601 datetime
  - `updated_before` - Filter runs updated before this ISO8601 datetime
  - `project_id` - The project the runs come from

  The service account must send `project_id` on the list, as these tables grow
  with every run; leaving it out is 400 `invalid_parameter`.

  ## Examples

      GET /api/runs?page=1&page_size=20
      GET /api/runs?inserted_after=2024-01-01T00:00:00Z
      GET /api/runs?inserted_after=2024-01-01T00:00:00Z&inserted_before=2024-12-31T23:59:59Z
      GET /api/projects/:project_id/runs?inserted_after=2024-01-01T00:00:00Z

  ## Sample curl requests

  List all runs:

  ```bash
  curl http://localhost:4000/api/runs \\
    -H "Authorization: Bearer $TOKEN"
  ```

  Get a single run:

  ```bash
  curl http://localhost:4000/api/runs/$RUN_ID \\
    -H "Authorization: Bearer $TOKEN"
  ```

  Filter by project, workflow, work order, or date range:

  ```bash
  curl "http://localhost:4000/api/runs?project_id=$PID&inserted_after=2024-01-01T00:00:00Z" \\
    -H "Authorization: Bearer $TOKEN"
  ```

  Nested route — runs for a specific project:

  ```bash
  curl http://localhost:4000/api/projects/$PROJECT_ID/runs \\
    -H "Authorization: Bearer $TOKEN"
  ```

  """
  use LightningWeb, :controller

  alias Lightning.Runs
  alias LightningWeb.API.Errors
  alias LightningWeb.API.FallbackController
  alias LightningWeb.API.Filters
  alias LightningWeb.API.Request
  alias LightningWeb.API.Target

  action_fallback FallbackController

  plug LightningWeb.Plugs.AuthorizeAction,
       {:project_users, :access_project}

  @doc """
  Lists the runs of the projects the caller may access, or of one project on the
  nested route, narrowed by the query's filters.

  The caller is authorised before the query is read, so a caller who may not see
  the project learns nothing from its filters. Every bad filter is reported in
  one 400 `invalid_parameter` (error-format spec §9.4).

  ## Examples

      GET /api/runs?page=2&page_size=50&state=failed,crashed
      GET /api/projects/a1b2c3d4-5e6f-7a8b-9c0d-1e2f3a4b5c6d/runs?inserted_after=2024-01-01T00:00:00Z
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
           |> Filters.runs(conn.assigns.scope)
           |> Errors.refuse_parameters() do
      list(project, conn, params, filters)
    end
  end

  def index(conn, params) do
    with {:ok, filters} <-
           params
           |> Filters.runs(conn.assigns.scope)
           |> Errors.refuse_parameters() do
      list(conn.assigns.scope, conn, params, filters)
    end
  end

  @doc """
  Shows a run to a caller who may access its project.

  On `/api/runs/:id`, `LightningWeb.API.Target.in_project_of/5` decides who
  learns that an id names no run. On the nested route the path's project is
  checked first, and a run outside it is 404 `not_found`.

  ## Examples

      GET /api/runs/a1b2c3d4-5e6f-7a8b-9c0d-1e2f3a4b5c6d
      GET /api/projects/a1b2c3d4-.../runs/a1b2c3d4-...
  """
  @spec show(Plug.Conn.t(), map()) :: Plug.Conn.t() | {:error, term()}
  def show(%{path_params: %{"project_id" => _}} = conn, _params) do
    with {:ok, run} <-
           Target.in_project(
             conn.assigns.scope,
             Request.param(conn, "project_id"),
             {:project_users, :access_project},
             Request.param(conn, "id"),
             &Runs.get_for_project(&1, &2, include: [work_order: :workflow])
           ) do
      render(conn, "show.json", run: run, conn: conn)
    end
  end

  def show(conn, _params) do
    with {:ok, run} <-
           Target.in_project_of(
             conn.assigns.scope,
             Request.param(conn, "id"),
             {:project_users, :access_project},
             &Runs.get_project_id/1,
             &Runs.get_for_project(&1, &2, include: [work_order: :workflow])
           ) do
      render(conn, "show.json", run: run, conn: conn)
    end
  end

  defp list(project_or_scope, conn, params, filters) do
    page =
      Runs.paginate_runs_for(project_or_scope, filters, Filters.page(params))

    render(conn, "index.json", page: page, filters: filters, conn: conn)
  end
end
