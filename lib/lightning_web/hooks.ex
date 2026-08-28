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
  alias Lightning.Policies.Users
  alias Lightning.Projects.Events
  alias Lightning.Projects.Events.ProjectUserAdded
  alias Lightning.Projects.Events.ProjectUserRemoved
  alias Lightning.Projects.Events.ProjectUserRoleChanged
  alias Lightning.Projects.Events.SupportAccessUpdated
  alias Lightning.Projects.ProjectLimiter
  alias Lightning.Projects.Scope
  alias Lightning.Services.UsageLimiter
  alias Lightning.VersionControl.VersionControlUsageLimiter
  alias LightningWeb.LiveHelpers

  # Gates the admin space. Halts the mount and redirects when the user can't
  # access it, so admin-only LiveViews can't be mounted (and their per-event
  # handlers can't be invoked) by a non-admin socket.
  def on_mount(
        :ensure_admin,
        _params,
        _session,
        %{assigns: %{current_user: nil}} = socket
      ) do
    {:halt, redirect(socket, to: ~p"/users/log_in")}
  end

  def on_mount(:ensure_admin, _params, _session, socket) do
    can_access_admin_space =
      Users
      |> Permissions.can?(:access_admin_space, socket.assigns.current_user, {})

    if can_access_admin_space do
      {:cont, socket}
    else
      {:halt,
       socket
       |> put_flash(:nav, :no_access)
       |> redirect(to: ~p"/projects")}
    end
  end

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
    project = Lightning.Projects.get_project(project_id)

    # Subscribe *before* the membership reads below. A revocation committed in
    # the gap between reading the role and subscribing would be missed, and
    # this socket would keep its mount-time permissions for as long as it lives
    # — the exact failure this hook exists to prevent.
    socket = watch_project_membership(socket, project)

    projects = Lightning.Projects.get_projects_for_user(current_user)

    project_user =
      project && Lightning.Projects.get_project_user(project, current_user)

    # One Scope, two questions. `:access_project` now refuses an MFA-blocked
    # member outright, so it can no longer tell "not a member" apart from
    # "member who hasn't enrolled" — and only the second may be told the
    # project exists. `blocked_by_mfa?/1` draws that line.
    case Scope.fetch(current_user, project) do
      {:ok, scope} ->
        cond do
          ProjectUsers.blocked_by_mfa?(scope) ->
            {:halt, redirect(socket, to: ~p"/mfa_required")}

          ProjectUsers.permitted?(:access_project, scope) ->
            access_root =
              Lightning.Projects.access_root_for_user(project, current_user)

            project_label =
              Lightning.Projects.display_name_within_access_root(
                project,
                access_root
              )

            {:cont,
             socket
             |> assign(:side_menu_theme, "primary-theme")
             |> assign(:project_user, project_user)
             |> assign(:project, project)
             |> assign(:access_root, access_root)
             |> assign(:project_label, project_label)
             |> assign(:projects, projects)}

          true ->
            {:halt,
             redirect(socket, to: "/projects") |> put_flash(:nav, :not_found)}
        end

      # No such project, or one scheduled for deletion. Both were already the
      # not-found redirect before Scope answered them here.
      {:error, _reason} ->
        {:halt, redirect(socket, to: "/projects") |> put_flash(:nav, :not_found)}
    end
  end

  def on_mount(:project_scope, _, _session, socket) do
    {:cont, socket}
  end

  def on_mount(
        :ensure_workflow_belongs_to_project,
        %{"id" => workflow_id},
        _session,
        %{assigns: %{project: project}} = socket
      ) do
    workflow_exists? =
      Lightning.Workflows.workflow_exists_in_project?(project.id, workflow_id)

    if workflow_exists? do
      {:cont, socket}
    else
      {:halt,
       socket
       |> put_flash(:error, "Workflow not found")
       |> redirect(to: ~p"/projects/#{project}/w")}
    end
  end

  def on_mount(
        :ensure_workflow_belongs_to_project,
        _params,
        _session,
        socket
      ) do
    {:cont, socket}
  end

  def on_mount(
        :ensure_run_belongs_to_project,
        %{"id" => run_id},
        _session,
        %{assigns: %{project: project}} = socket
      ) do
    if Lightning.Runs.get_for_project(run_id, project.id) do
      {:cont, socket}
    else
      {:halt,
       socket
       |> put_flash(:error, "Run not found")
       |> redirect(to: ~p"/projects/#{project}/history")}
    end
  end

  def on_mount(
        :ensure_run_belongs_to_project,
        _params,
        _session,
        socket
      ) do
    {:cont, socket}
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

  def on_mount(:check_limits, _params, _session, socket) do
    case socket.assigns do
      %{current_user: _user, project: %{id: project_id}} ->
        {:cont, LiveHelpers.check_limits(socket, project_id)}

      _ ->
        {:cont, socket}
    end
  end

  @project_user_events [
    ProjectUserAdded,
    ProjectUserRemoved,
    ProjectUserRoleChanged,
    SupportAccessUpdated
  ]

  # A mount-time authorisation decision is not durable: the ProjectUser row can
  # be written while the socket lives. Subscribe to the project's events and
  # re-mount on any change to our own membership, so `:project_scope` and every
  # mount-time permission assign are recomputed. A removed user is redirected
  # out by the re-mount itself.
  #
  # Every direction re-mounts, including additions: a support user added with a
  # narrower role than their support access would otherwise keep their wider
  # mount-time assigns, and "did this widen or narrow my access?" cannot be
  # answered from the event alone.
  #
  # Called before the caller has decided whether access is granted, so that no
  # revocation can slip through between the decision and the subscription. If
  # the mount goes on to halt, the subscription dies with the process.
  defp watch_project_membership(socket, nil), do: socket

  defp watch_project_membership(socket, project) do
    if connected?(socket) do
      Events.subscribe(project.id)

      attach_hook(
        socket,
        :project_user_events,
        :handle_info,
        &handle_project_user_event/2
      )
    else
      socket
    end
  end

  # Support access is project-wide, so there is no user to match on: the sockets
  # it speaks for are the ones holding the project by support access alone. A
  # membership row wins over support access while it exists, so those sessions
  # are untouched. Turning support access *on* cannot match a live socket, since
  # a support user without a row could not have mounted while it was off, which
  # is why this needs no direction check.
  defp handle_project_user_event(
         %SupportAccessUpdated{},
         %{
           assigns: %{
             current_user: %{support_user: true},
             project_user: nil
           }
         } = socket
       ) do
    {:halt, push_navigate(socket, to: remount_path(socket))}
  end

  defp handle_project_user_event(
         %event{user_id: user_id},
         %{assigns: %{current_user: %{id: user_id}}} = socket
       )
       when event in @project_user_events do
    {:halt, push_navigate(socket, to: remount_path(socket))}
  end

  # Somebody else's standing on the project — nothing to do, but halt so the
  # event never reaches a LiveView that has no matching `handle_info/2` clause.
  defp handle_project_user_event(%event{}, socket)
       when event in @project_user_events do
    {:halt, socket}
  end

  defp handle_project_user_event(_message, socket), do: {:cont, socket}

  # `:current_uri` is assigned by `LightningWeb.InitAssigns`, but only from
  # `handle_params` — fall back to the project's workflow index, which re-runs
  # the same `:project_scope` gate. The URI carries the query string, so the
  # re-mount keeps filters and panel params.
  defp remount_path(%{assigns: %{current_uri: uri}}) when is_binary(uri),
    do: uri

  defp remount_path(%{assigns: %{project: project}}),
    do: ~p"/projects/#{project}/w"
end
