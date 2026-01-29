defmodule LightningWeb.API.JobController do
  @moduledoc """
  API controller for job management.

  Provides read access to jobs within workflows. Jobs are JavaScript execution
  units that process data using OpenFn adaptors. Jobs belong to workflows and
  inherit access controls from their parent project.

  ## Query Parameters (index)

  - `page` - Page number (default: 1)
  - `page_size` - Number of items per page (default: 10)
  - `project_id` - Filter jobs by project UUID (optional)

  ## Examples

      GET /api/jobs
      GET /api/jobs?project_id=a1b2c3d4-...&page=1&page_size=20
      GET /api/jobs/a1b2c3d4-5e6f-7a8b-9c0d-1e2f3a4b5c6d
  """
  @moduledoc docout: true
  use LightningWeb, :controller

  alias Lightning.Jobs
  alias Lightning.Policies.Permissions
  alias Lightning.Policies.ProjectUsers
  alias Lightning.Workflows

  action_fallback LightningWeb.FallbackController

  @doc """
  Lists jobs with optional project filtering.

  This function has two variants:
  - With `project_id`: Returns jobs for a specific project
  - Without `project_id`: Returns jobs across all accessible projects

  Returns a paginated list of jobs.

  ## Parameters

  - `conn` - The Plug connection struct with the current resource assigned
  - `params` - Map containing:
    - `project_id` - Project UUID (optional, filters to specific project)
    - `page` - Page number (optional, default: 1)
    - `page_size` - Items per page (optional, default: 10)

  ## Returns

  - Renders JSON with paginated list of jobs
  - `404 Not Found` if project doesn't exist (when project_id provided)
  - `403 Forbidden` if user lacks project access (when project_id provided)

  ## Examples

      # All jobs accessible to user
      GET /api/jobs
      GET /api/jobs?page=3&page_size=25

      # Jobs for specific project
      GET /api/jobs?project_id=a1b2c3d4-5e6f-7a8b-9c0d-1e2f3a4b5c6d
      GET /api/jobs?project_id=a1b2c3d4-...&page=2&page_size=50
  """
  @spec index(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def index(conn, %{"project_id" => project_id} = params) do
    pagination_attrs = Map.take(params, ["page_size", "page"])

    with project <- Lightning.Projects.get_project(project_id),
         :ok <-
           ProjectUsers
           |> Permissions.can(
             :access_project,
             conn.assigns.current_resource,
             project
           ) do
      page =
        Jobs.jobs_for_project_query(project)
        |> Lightning.Repo.paginate(pagination_attrs)

      render(conn, "index.json", page: page, conn: conn)
    end
  end

  def index(conn, params) do
    pagination_attrs = Map.take(params, ["page_size", "page"])

    page =
      Workflows.Query.jobs_for(conn.assigns.current_resource)
      |> Lightning.Repo.paginate(pagination_attrs)

    render(conn, "index.json", page: page, conn: conn)
  end

  @doc """
  Retrieves a specific job by ID.

  Returns detailed information about a single job including its body, adaptor,
  and workflow association. Access is granted if the user has access to the
  job's parent project.

  ## Parameters

  - `conn` - The Plug connection struct with the current resource assigned
  - `params` - Map containing:
    - `id` - Job UUID (required)

  ## Returns

  - `200 OK` with job JSON on success
  - `404 Not Found` if job doesn't exist
  - `403 Forbidden` if user lacks project access

  ## Examples

      GET /api/jobs/a1b2c3d4-5e6f-7a8b-9c0d-1e2f3a4b5c6d
  """
  @spec show(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def show(conn, %{"id" => id}) do
    with job <- Jobs.get_job!(id),
         job_with_project <- Lightning.Repo.preload(job, workflow: :project),
         :ok <-
           ProjectUsers
           |> Permissions.can(
             :access_project,
             conn.assigns.current_resource,
             job_with_project.workflow.project
           ) do
      render(conn, "show.json", job: job, conn: conn)
    end
  end
end
