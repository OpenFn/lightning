defmodule LightningWeb.API.RunController do
  use LightningWeb, :controller

  alias Lightning.Projects.Project
  alias Lightning.Invocation
  # alias Lightning.Jobs.Job

  action_fallback(LightningWeb.FallbackController)

  def index(conn, %{"project_id" => project_id} = params) do
    pagination_attrs = Map.take(params, ["page_size", "page"])

    with project = %Project{} <-
           Lightning.Projects.get_project(project_id) || {:error, :not_found},
         :ok <-
           Bodyguard.permit(
             Invocation.Policy,
             :list_runs,
             conn.assigns.current_user,
             project
           ) do
      page = Invocation.list_runs_for_project(project, pagination_attrs)

      render(conn, "index.json", %{page: page, conn: conn})
    end
  end

  def index(conn, params) do
    pagination_attrs = Map.take(params, ["page_size", "page"])

    page =
      Invocation.Query.runs_for(conn.assigns.current_user)
      |> Lightning.Repo.paginate(pagination_attrs)

    render(conn, "index.json", %{page: page, conn: conn})
  end

  def show(conn, %{"id" => id}) do
    with run <- Invocation.get_run!(id),
         :ok <-
           Bodyguard.permit(
             Invocation.Policy,
             :read_run,
             conn.assigns.current_user,
             run
           ) do
      render(conn, "show.json", %{run: run, conn: conn})
    end
  end
end
