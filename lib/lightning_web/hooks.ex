defmodule LightningWeb.Hooks do
  @moduledoc """
  LiveView Hooks with Sandbox Support
  """
  use LightningWeb, :verified_routes

  import Phoenix.Component
  import Phoenix.LiveView

  alias Lightning.Extensions.UsageLimiting.Action
  alias Lightning.Extensions.UsageLimiting.Context
  alias Lightning.Policies.Permissions
  alias Lightning.Policies.ProjectUsers
  alias Lightning.Projects
  alias Lightning.Projects.Project
  alias Lightning.Projects.ProjectLimiter
  alias Lightning.Services.UsageLimiter
  alias Lightning.VersionControl.VersionControlUsageLimiter
  alias LightningWeb.Live.Helpers.ProjectTheme

  @doc """
  Finds and assigns a project to the socket, handling both sandbox-aware and legacy routes.

  For sandbox routes (/projects/:project_id/:sandbox_name/*):
  - Validates the parent project access
  - Resolves and assigns the specific sandbox as current_project

  For legacy routes:
  - Maintains existing behavior for backward compatibility
  """

  def on_mount(
        :project_scope,
        _params,
        _session,
        %{assigns: %{current_user: nil}} = socket
      ) do
    {:halt, redirect(socket, to: ~p"/users/log_in")}
  end

  def on_mount(
        :project_scope,
        %{"project_id" => project_id} = params,
        _session,
        %{assigns: %{current_user: current_user}} = socket
      ) do
    case Projects.get_project(project_id) do
      nil ->
        {:halt, redirect(socket, to: "/projects") |> put_flash(:nav, :not_found)}

      found_project ->
        parent_project = Projects.root_of(found_project)

        case resolve_current_project(parent_project, found_project, params) do
          {:ok, current_project} ->
            handle_project_access(
              socket,
              current_user,
              parent_project,
              current_project
            )

          {:error, :invalid_sandbox} ->
            {:halt, redirect(socket, to: "/projects/#{project_id}/main")}
        end
    end
  end

  def on_mount(:project_scope, _, _session, socket) do
    {:cont, assign_new(socket, :theme_style, fn -> nil end)}
  end

  def on_mount(:assign_projects, _, _session, socket) do
    %{current_user: current_user} = socket.assigns
    projects = Projects.get_projects_for_user(current_user)

    {:cont, socket |> assign_new(:projects, fn -> projects end)}
  end

  def on_mount(:limit_github_sync, _params, _session, socket) do
    project_id = get_project_for_limits(socket).id

    case VersionControlUsageLimiter.limit_github_sync(project_id) do
      :ok ->
        {:cont, socket}

      {:error, %{function: func} = component} when is_function(func) ->
        {:cont, assign(socket, github_banner: component)}
    end
  end

  def on_mount(:limit_mfa, _params, _session, socket) do
    project_id = get_project_for_limits(socket).id

    case UsageLimiter.limit_action(
           %Action{type: :require_mfa},
           %Context{project_id: project_id}
         ) do
      :ok ->
        {:cont, assign(socket, can_require_mfa: true)}

      {:error, _reason, %{function: func} = component} when is_function(func) ->
        {:cont, assign(socket, mfa_banner: component, can_require_mfa: false)}
    end
  end

  def on_mount(:limit_retention_periods, _params, _session, socket) do
    project = get_project_for_limits(socket)
    retention_periods = ProjectLimiter.get_data_retention_periods(project.id)
    retention_message = ProjectLimiter.get_data_retention_message(project.id)

    {:cont,
     assign(socket,
       data_retention_periods: retention_periods,
       data_retention_limit_message: retention_message
     )}
  end

  defp resolve_current_project(parent_project, _found_project, %{
         "sandbox_name" => sandbox_name
       }) do
    case Projects.get_sandbox_by_name(parent_project.id, sandbox_name) do
      %Project{} = sandbox -> {:ok, sandbox}
      nil -> {:error, :invalid_sandbox}
    end
  end

  defp resolve_current_project(_parent_project, found_project, _params) do
    {:ok, found_project}
  end

  defp handle_project_access(
         socket,
         current_user,
         parent_project,
         current_project
       ) do
    case Permissions.can?(
           ProjectUsers,
           :access_project,
           current_user,
           parent_project
         ) do
      false ->
        {:halt, redirect(socket, to: "/projects") |> put_flash(:nav, :not_found)}

      true ->
        cond do
          parent_project.requires_mfa and !current_user.mfa_enabled ->
            {:halt, redirect(socket, to: ~p"/mfa_required")}

          true ->
            projects = Projects.get_projects_for_user(current_user)

            project_user =
              Projects.get_project_user(parent_project, current_user)

            assign_project_context(
              socket,
              parent_project,
              current_project,
              project_user,
              projects
            )
        end
    end
  end

  defp assign_project_context(
         socket,
         parent_project,
         current_project,
         project_user,
         projects
       ) do
    scale = ProjectTheme.inline_primary_scale(current_project)

    theme_style =
      [scale, ProjectTheme.inline_sidebar_vars()]
      |> Enum.reject(&is_nil/1)
      |> Enum.join(" ")

    {:cont,
     socket
     |> assign(:side_menu_theme, "primary-theme")
     |> assign(:theme_style, theme_style)
     |> assign_new(:project_user, fn -> project_user end)
     |> assign_new(:project, fn -> parent_project end)
     |> assign_new(:current_project, fn -> current_project end)
     |> assign_new(:parent_project, fn -> parent_project end)
     |> assign_new(:current_sandbox, fn ->
       if Project.sandbox?(current_project), do: current_project, else: nil
     end)
     |> assign_new(:projects, fn -> projects end)}
  end

  # Helper to determine which project to use for limits
  # Limits are typically applied at the workspace (parent) level
  defp get_project_for_limits(socket) do
    socket.assigns[:parent_project] || socket.assigns[:project]
  end
end
