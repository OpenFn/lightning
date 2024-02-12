# defmodule LightningWeb.API.RunController do
#   use LightningWeb, :controller

#   alias Lightning.Invocation
#   alias Lightning.Policies.Permissions
#   alias Lightning.Policies.ProjectUsers
#   alias Lightning.Projects.Project
#   alias Lightning.Repo

#   action_fallback LightningWeb.FallbackController

#   def index(conn, %{"project_id" => project_id} = params) do
#     pagination_attrs = Map.take(params, ["page_size", "page"])

#     with project = %Project{} <-
#            Lightning.Projects.get_project(project_id) || {:error, :not_found},
#          :ok <-
#            ProjectUsers
#            |> Permissions.can(
#              :access_project,
#              conn.assigns.current_user,
#              project
#            ) do
#       page = Invocation.list_runs_for_project(project, pagination_attrs)

#       render(conn, "index.json", %{page: page, conn: conn})
#     end
#   end

#   def index(conn, params) do
#     pagination_attrs = Map.take(params, ["page_size", "page"])

#     page =
#       Invocation.Query.runs_for(conn.assigns.current_user)
#       |> Lightning.Repo.paginate(pagination_attrs)

#     render(conn, "index.json", %{page: page, conn: conn})
#   end

#   def show(conn, %{"id" => id}) do
#     with run <- Invocation.get_run_with_job!(id),
#          :ok <-
#            ProjectUsers
#            |> Permissions.can(
#              :access_project,
#              conn.assigns.current_user,
#              Repo.preload(run.job, :project).project
#            ) do
#       render(conn, "show.json", %{run: run, conn: conn})
#     end
#   end
# end
