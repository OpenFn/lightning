defmodule LightningWeb.API.JobController do
  @moduledoc """
  API controller for job management.

  Provides read access to jobs within workflows. Jobs are JavaScript execution
  units that process data using OpenFn adaptors. Jobs belong to workflows and
  inherit access controls from their parent project.

  ## Query Parameters (index)

  - `page` - Page number (default: 1)
  - `page_size` - Number of items per page (default: 10, at most 100)
  - `project_id` - Filter jobs by project UUID (optional)

  ## Examples

      GET /api/jobs
      GET /api/jobs?project_id=a1b2c3d4-...&page=1&page_size=20
      GET /api/jobs/a1b2c3d4-5e6f-7a8b-9c0d-1e2f3a4b5c6d

  ## Sample curl requests

  List all jobs:

  ```bash
  curl http://localhost:4000/api/jobs \\
    -H "Authorization: Bearer $TOKEN"
  ```

  Get a single job:

  ```bash
  curl http://localhost:4000/api/jobs/$JOB_ID \\
    -H "Authorization: Bearer $TOKEN"
  ```

  Filter by project:

  ```bash
  curl "http://localhost:4000/api/jobs?project_id=$PROJECT_ID" \\
    -H "Authorization: Bearer $TOKEN"
  ```

  Nested route — jobs for a specific project:

  ```bash
  curl http://localhost:4000/api/projects/$PROJECT_ID/jobs \\
    -H "Authorization: Bearer $TOKEN"
  ```
  """
  use LightningWeb, :controller

  alias Lightning.Jobs
  alias LightningWeb.API.FallbackController
  alias LightningWeb.API.Filters
  alias LightningWeb.API.Request
  alias LightningWeb.API.Target

  action_fallback FallbackController

  plug LightningWeb.Plugs.AuthorizeAction,
       {:project_users, :access_project}

  @doc """
  Lists the jobs of the projects the caller may access, or of one project named
  by the nested route or the `project_id` parameter.

  ## Examples

      GET /api/jobs?page=3&page_size=25
      GET /api/jobs?project_id=a1b2c3d4-5e6f-7a8b-9c0d-1e2f3a4b5c6d
      GET /api/projects/a1b2c3d4-5e6f-7a8b-9c0d-1e2f3a4b5c6d/jobs
  """
  @spec index(Plug.Conn.t(), map()) :: Plug.Conn.t() | {:error, term()}
  def index(conn, %{"project_id" => _} = params) do
    with {:ok, project} <-
           Target.project(
             conn.assigns.scope,
             Request.param(conn, "project_id"),
             {:project_users, :access_project}
           ) do
      list(project, conn, params, %{project_id: project.id})
    end
  end

  def index(conn, params) do
    list(conn.assigns.scope, conn, params, %{})
  end

  @doc """
  Shows a job to a caller who may access its project.

  On `/api/jobs/:id`, `LightningWeb.API.Target.in_project_of/5` decides who
  learns that an id names no job. On the nested route the path's project is
  checked first, and a job outside it is 404 `not_found`.

  ## Examples

      GET /api/jobs/a1b2c3d4-5e6f-7a8b-9c0d-1e2f3a4b5c6d
      GET /api/projects/a1b2c3d4-.../jobs/a1b2c3d4-...
  """
  @spec show(Plug.Conn.t(), map()) :: Plug.Conn.t() | {:error, term()}
  def show(%{path_params: %{"project_id" => _}} = conn, _params) do
    with {:ok, job} <-
           Target.in_project(
             conn.assigns.scope,
             Request.param(conn, "project_id"),
             {:project_users, :access_project},
             Request.param(conn, "id"),
             &Jobs.get_job_for_project(&1, &2, include: [:workflow])
           ) do
      render(conn, "show.json", job: job, conn: conn)
    end
  end

  def show(conn, _params) do
    with {:ok, job} <-
           Target.in_project_of(
             conn.assigns.scope,
             Request.param(conn, "id"),
             {:project_users, :access_project},
             &Jobs.get_project_id/1,
             &Jobs.get_job_for_project(&1, &2, include: [:workflow])
           ) do
      render(conn, "show.json", job: job, conn: conn)
    end
  end

  defp list(project_or_scope, conn, params, filters) do
    page = Jobs.paginate_jobs_for(project_or_scope, Filters.page(params))

    render(conn, "index.json", page: page, filters: filters, conn: conn)
  end
end
