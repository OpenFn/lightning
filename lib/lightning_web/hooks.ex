defmodule LightningWeb.Hooks do
  @moduledoc """
  LiveView Hooks
  """
  use LightningWeb, :verified_routes

  import Phoenix.Component
  import Phoenix.LiveView

  alias Lightning.Extensions.UsageLimiting.Action
  alias Lightning.Extensions.UsageLimiting.Context
  alias Lightning.Policies.Permissions
  alias Lightning.Policies.ProjectUsers
  alias Lightning.Projects.ProjectLimiter
  alias Lightning.Services.UsageLimiter
  alias Lightning.VersionControl.VersionControlUsageLimiter
  alias LightningWeb.Live.Helpers.ProjectTheme

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
    {:halt, redirect(socket, to: ~p"/users/log_in")}
  end

  def on_mount(
        :project_scope,
        %{"project_id" => project_id},
        _session,
        %{assigns: %{current_user: current_user}} = socket
      ) do
    current = Lightning.Projects.get_project(project_id)
    root = if current, do: Lightning.Projects.root_of(current)
    projects = Lightning.Projects.get_projects_for_user(current_user)

    project_user =
      root && Lightning.Projects.get_project_user(root, current_user)

    can_access_project =
      Permissions.can?(ProjectUsers, :access_project, current_user, root)

    cond do
      can_access_project and root.requires_mfa and !current_user.mfa_enabled ->
        {:halt, redirect(socket, to: ~p"/mfa_required")}

      can_access_project ->
        sandboxes = Lightning.Projects.list_sandboxes(root.id)
        scale = ProjectTheme.inline_primary_scale(project)

        theme_style =
          [scale, ProjectTheme.inline_sidebar_vars()]
          |> Enum.reject(&is_nil/1)
          |> Enum.join(" ")

        {:cont,
         socket
         |> assign(:side_menu_theme, "primary-theme")
         |> assign(:theme_style, theme_style)
         |> assign_new(:project_user, fn -> project_user end)
         |> assign_new(:project, fn -> root end)
         |> assign_new(:projects, fn -> projects end)
         |> assign_new(:sandboxes, fn -> sandboxes end)}

      true ->
        {:halt, redirect(socket, to: "/projects") |> put_flash(:nav, :not_found)}
    end
  end

  def on_mount(:project_scope, _, _session, socket) do
    {:cont, assign_new(socket, :theme_style, fn -> nil end)}
  end

  def on_mount(:assign_projects, _, _session, socket) do
    %{current_user: current_user} = socket.assigns

    projects = Lightning.Projects.get_projects_for_user(current_user)

    {:cont,
     socket
     |> assign_new(:projects, fn -> projects end)}
  end

  def on_mount(:limit_github_sync, _params, _session, socket) do
    case VersionControlUsageLimiter.limit_github_sync(socket.assigns.project.id) do
      :ok ->
        {:cont, socket}

      {:error, %{function: func} = component} when is_function(func) ->
        {:cont, assign(socket, github_banner: component)}
    end
  end

  def on_mount(:limit_mfa, _params, _session, socket) do
    case UsageLimiter.limit_action(
           %Action{type: :require_mfa},
           %Context{
             project_id: socket.assigns.project.id
           }
         ) do
      :ok ->
        {:cont, assign(socket, can_require_mfa: true)}

      {:error, _reason, %{function: func} = component} when is_function(func) ->
        {:cont, assign(socket, mfa_banner: component, can_require_mfa: false)}
    end
  end

  def on_mount(:limit_retention_periods, _params, _session, socket) do
    %{project: project} = socket.assigns
    retention_periods = ProjectLimiter.get_data_retention_periods(project.id)
    retention_message = ProjectLimiter.get_data_retention_message(project.id)

    {:cont,
     assign(socket,
       data_retention_periods: retention_periods,
       data_retention_limit_message: retention_message
     )}
  end
end
