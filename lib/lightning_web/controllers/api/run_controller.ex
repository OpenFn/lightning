defmodule LightningWeb.API.RunController do
  @moduledoc """
  API controller for managing runs.

  ## Query Parameters

  - `page` - Page number (default: 1)
  - `page_size` - Number of items per page (default: 10)
  - `inserted_after` - Filter runs created after this ISO8601 datetime
  - `inserted_before` - Filter runs created before this ISO8601 datetime
  - `updated_after` - Filter runs updated after this ISO8601 datetime
  - `updated_before` - Filter runs updated before this ISO8601 datetime

  ## Examples

      GET /api/runs?page=1&page_size=20
      GET /api/runs?inserted_after=2024-01-01T00:00:00Z
      GET /api/runs?inserted_after=2024-01-01T00:00:00Z&inserted_before=2024-12-31T23:59:59Z
      GET /api/projects/:project_id/runs?inserted_after=2024-01-01T00:00:00Z

  """
  use LightningWeb, :controller

  alias Lightning.Invocation
  alias Lightning.Policies.Permissions
  alias Lightning.Policies.ProjectUsers
  alias Lightning.Runs

  action_fallback LightningWeb.FallbackController

  @doc """
  Lists runs with optional project filtering.

  This function has two variants:
  - With `project_id`: Returns runs for a specific project
  - Without `project_id`: Returns runs across all accessible projects

  Returns a paginated list of runs with optional datetime filtering.

  ## Parameters

  - `conn` - The Plug connection struct with the current resource assigned
  - `params` - Map containing:
    - `project_id` - Project UUID (optional, filters to specific project)
    - `page` - Page number (optional, default: 1)
    - `page_size` - Items per page (optional, default: 10)
    - `inserted_after` - Filter runs created after ISO8601 datetime (optional)
    - `inserted_before` - Filter runs created before ISO8601 datetime (optional)
    - `updated_after` - Filter runs updated after ISO8601 datetime (optional)
    - `updated_before` - Filter runs updated before ISO8601 datetime (optional)

  ## Returns

  - Renders JSON with paginated list of runs
  - `404 Not Found` if project doesn't exist (when project_id provided)
  - `403 Forbidden` if user lacks project access (when project_id provided)
  - `422 Unprocessable Entity` if datetime parameters are invalid

  ## Examples

      # All runs accessible to user
      GET /api/runs
      GET /api/runs?page=2&page_size=50
      GET /api/runs?inserted_after=2024-01-01T00:00:00Z

      # Runs for specific project
      GET /api/projects/a1b2c3d4-5e6f-7a8b-9c0d-1e2f3a4b5c6d/runs
      GET /api/projects/a1b2c3d4-5e6f-7a8b-9c0d-1e2f3a4b5c6d/runs?page=2
      GET /api/projects/a1b2c3d4-5e6f-7a8b-9c0d-1e2f3a4b5c6d/runs?inserted_after=2024-01-01T00:00:00Z
  """
  @spec index(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def index(conn, %{"project_id" => project_id} = params) do
    pagination_attrs = Map.take(params, ["page_size", "page"])

    with :ok <-
           Invocation.Query.validate_datetime_params(params, [
             "inserted_after",
             "inserted_before",
             "updated_after",
             "updated_before"
           ]),
         project <- Lightning.Projects.get_project(project_id),
         :ok <-
           ProjectUsers
           |> Permissions.can(
             :access_project,
             conn.assigns.current_resource,
             project
           ) do
      page =
        Runs.runs_for_project_query(project)
        |> Invocation.Query.filter_runs(params)
        |> Lightning.Repo.paginate(pagination_attrs)

      render(conn, "index.json", page: page, conn: conn)
    end
  end

  def index(conn, params) do
    with :ok <-
           Invocation.Query.validate_datetime_params(params, [
             "inserted_after",
             "inserted_before",
             "updated_after",
             "updated_before"
           ]) do
      pagination_attrs = Map.take(params, ["page_size", "page"])

      page =
        Runs.runs_for_user_query(conn.assigns.current_resource)
        |> Invocation.Query.filter_runs(params)
        |> Lightning.Repo.paginate(pagination_attrs)

      render(conn, "index.json", page: page, conn: conn)
    end
  end

  @doc """
  Retrieves a specific run by ID.

  Returns detailed information about a single run including its associated
  work order and workflow. Access is granted if the user has access to the
  run's parent project.

  ## Parameters

  - `conn` - The Plug connection struct with the current resource assigned
  - `params` - Map containing:
    - `id` - Run UUID (required)

  ## Returns

  - `200 OK` with run JSON including work order and workflow
  - `404 Not Found` if run doesn't exist
  - `403 Forbidden` if user lacks project access

  ## Examples

      GET /api/runs/a1b2c3d4-5e6f-7a8b-9c0d-1e2f3a4b5c6d
  """
  @spec show(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def show(conn, %{"id" => id}) do
    with run <- Runs.get(id, include: [work_order: [workflow: :project]]),
         :ok <-
           ProjectUsers
           |> Permissions.can(
             :access_project,
             conn.assigns.current_resource,
             run.work_order.workflow.project
           ) do
      render(conn, "show.json", run: run, conn: conn)
    end
  end
end
