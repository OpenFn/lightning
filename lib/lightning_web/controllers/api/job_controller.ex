defmodule LightningWeb.API.JobController do
  use LightningWeb, :controller

  alias Lightning.Jobs
  alias Lightning.Policies.Permissions
  alias Lightning.Policies.ProjectUsers
  alias Lightning.Workflows

  action_fallback LightningWeb.FallbackController

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
