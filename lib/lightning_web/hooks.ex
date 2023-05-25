defmodule LightningWeb.Hooks do
  @moduledoc """
  LiveView Hooks
  """
  alias Lightning.Policies.Permissions
  alias Lightning.Policies.ProjectUsers
  import Phoenix.LiveView
  import Phoenix.Component

  @doc """
  Finds and assigns a project to the socket, if a user doesn't have access
  they are redirected and shown a 'No Access' screen via a `:nav` flash message.

  There is a fallthru function, when there is no `project_id` in the params -
  this is for liveviews that may or may not have a `project_id` depending on
  usage - like `DashboardLive`.
  """
  def on_mount(:project_scope, %{"project_id" => project_id}, _session, socket) do
    project = Lightning.Projects.get_project(project_id)

    projects =
      Lightning.Projects.get_projects_for_user(socket.assigns.current_user)

    can_access_project =
      ProjectUsers
      |> Permissions.can?(:access_project, socket.assigns.current_user, project)

    if can_access_project do
      {:cont,
       socket
       |> assign_new(:project, fn -> project end)
       |> assign_new(:projects, fn -> projects end)}
    else
      {:halt, redirect(socket, to: "/") |> put_flash(:nav, :no_access)}
    end
  end

  def on_mount(:project_scope, _, _session, socket) do
    {:cont, socket}
  end
end
