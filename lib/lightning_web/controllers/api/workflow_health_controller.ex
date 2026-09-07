defmodule LightningWeb.API.WorkflowHealthController do
  @moduledoc """
  Aggregate stats for the workflow health page.

  Cookie-authenticated, because the only caller is the React component the
  health LiveView mounts. This is its own trust boundary — the LiveView's
  `on_mount` guards do not protect it, since a client can request any path.
  Access to the project is re-checked here, via the same policy the rest of the
  app uses, so support users get in and soft-deleted projects don't.

  One action per chart, so a cheap chart isn't held up by an expensive one.
  """
  use LightningWeb, :controller

  alias Lightning.Policies.Permissions
  alias Lightning.Projects.Project
  alias Lightning.Workflows

  plug :authorize_workflow
  # After :authorize_workflow so a 404 wins over a 400.
  plug :validate_days

  def outcomes(conn, _params) do
    json(
      conn,
      Workflows.Stats.outcomes(conn.assigns.workflow, conn.assigns.days_back)
    )
  end

  def failure_signatures(conn, _params) do
    json(
      conn,
      Workflows.Stats.failure_signatures(
        conn.assigns.workflow,
        conn.assigns.days_back
      )
    )
  end

  # Closed set, string-matched — no free integer, no parse to defend.
  @days %{"1" => 1, "7" => 7, "30" => 30}
  @default_days "30"

  defp validate_days(conn, _opts) do
    case Map.fetch(@days, conn.params["days"] || @default_days) do
      {:ok, days_back} ->
        assign(conn, :days_back, days_back)

      :error ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "days must be one of 1, 7, 30"})
        |> halt()
    end
  end

  defp authorize_workflow(conn, _opts) do
    %{"project_id" => project_id, "workflow_id" => workflow_id} = conn.params

    with %_{} = user <- conn.assigns[:current_user],
         {:ok, project_id} <- Ecto.UUID.cast(project_id),
         %{project: project} = workflow <-
           Workflows.get_workflow_for_project(
             %Project{id: project_id},
             workflow_id,
             include: [:project]
           ),
         :ok <- Permissions.can(:project_users, :access_project, user, project) do
      assign(conn, :workflow, workflow)
    else
      # 404 for every failure, not 403: a 403 would confirm the workflow exists
      # to someone who can't see the project.
      _ ->
        conn
        |> put_status(:not_found)
        |> put_view(LightningWeb.ErrorView)
        |> render(:"404")
        |> halt()
    end
  end
end
