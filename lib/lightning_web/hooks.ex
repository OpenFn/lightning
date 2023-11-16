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
  def on_mount(
        :project_scope,
        _params,
        _session,
        %{assigns: %{current_user: nil}} = socket
      ) do
    # redirect if there's no current user
    {:halt, redirect(socket, to: "/")}
  end

  def on_mount(:project_scope, %{"project_id" => project_id}, _session, socket) do
    %{current_user: current_user} = socket.assigns

    project = Lightning.Projects.get_project(project_id)

    projects = Lightning.Projects.get_projects_for_user(current_user)

    project_user =
      project && Lightning.Projects.get_project_user(project, current_user)

    can_access_project =
      ProjectUsers
      |> Permissions.can?(:access_project, current_user, project)

    cond do
      can_access_project and project.requires_mfa and !current_user.mfa_enabled ->
        {:halt, redirect(socket, to: "/mfa_required")}

      can_access_project ->
        {:cont,
         socket
         |> assign_new(:project_user, fn -> project_user end)
         |> assign_new(:project, fn -> project end)
         |> assign_new(:projects, fn -> projects end)}

      true ->
        {:halt, redirect(socket, to: "/") |> put_flash(:nav, :not_found)}
    end
  end

  def on_mount(:project_scope, _, _session, socket) do
    {:cont, socket}
  end

  def on_mount(:assign_projects, _, _session, socket) do
    %{current_user: current_user} = socket.assigns

    projects = Lightning.Projects.get_projects_for_user(current_user)

    {:cont,
     socket
     |> assign_new(:projects, fn -> projects end)}
  end
end
