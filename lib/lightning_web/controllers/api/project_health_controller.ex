defmodule LightningWeb.API.ProjectHealthController do
  @moduledoc """
  Aggregate stats for the project health page.

  Cookie-authenticated, because the only caller is the React component the
  health LiveView mounts. This is its own trust boundary — the LiveView's
  `on_mount` guards do not protect it, since a client can request any path.
  Access to the project is re-checked here, via the same policy the rest of the
  app uses, so support users get in and soft-deleted projects don't.
  """
  use LightningWeb, :controller

  alias Lightning.Policies.Permissions
  alias Lightning.Projects
  alias Lightning.Projects.Project
  alias Lightning.Workflows

  plug :authorize_project

  def outcomes(conn, _params) do
    json(conn, Workflows.Stats.outcomes(conn.assigns.project))
  end

  defp authorize_project(conn, _opts) do
    %{"project_id" => project_id} = conn.params

    with %_{} = user <- conn.assigns[:current_user],
         {:ok, project_id} <- Ecto.UUID.cast(project_id),
         %Project{} = project <- Projects.get_project(project_id),
         :ok <- Permissions.can(:project_users, :access_project, user, project) do
      assign(conn, :project, project)
    else
      # 404 for every failure, not 403: a 403 would confirm the project exists
      # to someone who can't see it.
      _ ->
        conn
        |> put_status(:not_found)
        |> put_view(LightningWeb.ErrorView)
        |> render(:"404")
        |> halt()
    end
  end
end
