defmodule LightningWeb.API.ProjectController do
  use LightningWeb, :controller

  alias Lightning.Projects
  # alias Lightning.Jobs.Job

  action_fallback(LightningWeb.FallbackController)

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
           Bodyguard.permit(
             Projects.Policy,
             :read,
             conn.assigns.current_user,
             project
           ) do
      render(conn, "show.json", project: project, conn: conn)
    end
  end

  def create(conn, %{"data" => project_data}) do
    IO.inspect(project_data, label: "PROJECTDATA")

    {:ok, %{project: project}} =
      Lightning.Projects.import_project(project_data, conn.assigns.current_user)

    # IO.inspect(project, label: "PROJECT")
    # render(conn, "create.json", project: %{}, conn: conn)
  end
end
