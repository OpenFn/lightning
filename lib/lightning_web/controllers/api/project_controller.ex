defmodule LightningWeb.API.ProjectController do
  use LightningWeb, :controller

  alias Lightning.Policies.Permissions
  alias Lightning.Policies.ProjectUsers
  alias Lightning.Projects

  action_fallback LightningWeb.FallbackController

  def index(conn, params) do
    pagination_attrs = Map.take(params, ["page_size", "page"])

    page =
      Projects.projects_for_user_query(conn.assigns.current_user)
      |> Lightning.Repo.paginate(pagination_attrs)

    render(conn, "index.json", page: page, conn: conn)
  end

  def show(conn, %{"id" => id}) do
    with project <- Projects.get_project(id),
         :ok <-
           ProjectUsers
           |> Permissions.can(
             :access_project,
             conn.assigns.current_user,
             project
           ) do
      render(conn, "show.json", project: project, conn: conn)
    end
  end
end
