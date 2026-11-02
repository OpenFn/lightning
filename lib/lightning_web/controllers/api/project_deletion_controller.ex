defmodule LightningWeb.API.ProjectDeletionController do
  @moduledoc """
  Scheduling a project for deletion, and cancelling that.

  `DELETE /api/projects/:id` schedules the project, or the sandbox and every
  sandbox below it, for deletion and answers 204. Lightning removes it after
  the instance's retention period. A project already scheduled answers 409
  `scheduled_for_deletion`.

  `DELETE /api/projects/:id/scheduled_deletion` cancels a scheduled deletion
  and answers 200 with the project. It is the one route on a project that a
  scheduled project doesn't refuse with 409. A project that isn't scheduled
  answers 404 `not_found`.

  Who may do either is `Lightning.Policies.ProjectDeletion`: a root project's
  owner, a sandbox's owners and admins and those of the project at the top of
  its tree, and the service account.
  """
  use LightningWeb, :controller

  alias Lightning.Projects
  alias Lightning.Projects.Project
  alias Lightning.Projects.Sandboxes
  alias LightningWeb.API.FallbackController
  alias LightningWeb.API.Request
  alias LightningWeb.API.Target
  alias LightningWeb.Plugs.AuthorizeAction

  action_fallback FallbackController

  plug AuthorizeAction,
       {:project_deletion, :delete_project}
       when action == :delete

  plug AuthorizeAction,
       {:project_deletion, :cancel_project_deletion}
       when action == :cancel

  @spec delete(Plug.Conn.t(), map()) :: Plug.Conn.t() | {:error, term()}
  def delete(conn, _params) do
    with {:ok, project} <-
           Target.project(
             conn.assigns.scope,
             Request.param(conn, "id"),
             {:project_deletion, :delete_project}
           ),
         {:ok, _project} <-
           schedule(project, conn.assigns.current_resource) do
      send_resp(conn, :no_content, "")
    end
  end

  @spec cancel(Plug.Conn.t(), map()) :: Plug.Conn.t() | {:error, term()}
  def cancel(conn, _params) do
    with {:ok, project} <-
           Target.project(
             conn.assigns.scope,
             Request.param(conn, "id"),
             {:project_deletion, :cancel_project_deletion}
           ),
         :ok <- scheduled(project),
         {:ok, project} <- restore(project, conn.assigns.current_resource) do
      conn
      |> put_view(json: LightningWeb.API.ProjectJSON)
      |> render("show.json",
        project: Projects.get_project_with_users!(project.id),
        conn: conn
      )
    end
  end

  defp scheduled(%Project{scheduled_deletion: nil}), do: {:error, :not_found}
  defp scheduled(%Project{}), do: :ok

  defp schedule(%Project{parent_id: nil} = project, actor),
    do: Projects.schedule_project_deletion(project, actor)

  defp schedule(sandbox, actor),
    do: sandbox |> Sandboxes.schedule_sandbox_deletion(actor) |> as_forbidden()

  defp restore(%Project{parent_id: nil} = project, actor),
    do: Projects.cancel_scheduled_deletion(project, actor)

  defp restore(sandbox, actor),
    do:
      sandbox
      |> Sandboxes.cancel_scheduled_sandbox_deletion(actor)
      |> as_forbidden()

  # The sandbox functions ask their own policy again. It agrees with
  # `ProjectDeletion`, so this only answers a disagreement as a refusal rather
  # than a crash.
  defp as_forbidden({:error, :unauthorized}), do: {:error, :forbidden}
  defp as_forbidden(result), do: result
end
