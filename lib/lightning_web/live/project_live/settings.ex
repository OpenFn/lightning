defmodule LightningWeb.ProjectLive.Settings do
  @moduledoc """
  Index Liveview for project settings
  """

  use LightningWeb, :live_view

  alias Lightning.Accounts.User
  alias Lightning.Credentials
  alias Lightning.Policies.Permissions
  alias Lightning.Policies.ProjectUsers
  alias Lightning.Projects
  alias Lightning.Projects.Project
  alias Lightning.Projects.ProjectUser
  alias Lightning.VersionControl
  alias Lightning.VersionControl.GithubError
  alias Lightning.WebhookAuthMethods
  alias Lightning.Workflows.WebhookAuthMethod
  alias LightningWeb.Components.Form
  alias LightningWeb.ProjectLive.DeleteConnectionModal

  require Logger

  on_mount {LightningWeb.Hooks, :project_scope}

  @impl true
  def mount(_params, _session, socket) do
    %{project: project, current_user: current_user} = socket.assigns

    project_users =
      Projects.get_project_users!(project.id)

    credentials = Credentials.list_credentials(project)
    auth_methods = WebhookAuthMethods.list_for_project(project)

    can_delete_project =
      ProjectUsers
      |> Permissions.can?(
        :delete_project,
        current_user,
        project
      )

    can_edit_project =
      ProjectUsers
      |> Permissions.can?(
        :edit_project,
        current_user,
        project
      )

    project_user =
      Enum.find(project_users, fn project_user ->
        project_user.user_id == current_user.id
      end)

    can_edit_data_retention =
      Permissions.can?(
        ProjectUsers,
        :edit_data_retention,
        current_user,
        project_user
      )

    can_write_webhook_auth_method =
      Permissions.can?(
        ProjectUsers,
        :write_webhook_auth_method,
        current_user,
        project_user
      )

    can_write_github_connection =
      Permissions.can?(
        ProjectUsers,
        :write_github_connection,
        current_user,
        project_user
      )

    can_initiate_github_sync =
      Permissions.can?(
        ProjectUsers,
        :initiate_github_sync,
        current_user,
        project_user
      )

    can_create_project_credential =
      Permissions.can?(
        ProjectUsers,
        :create_project_credential,
        current_user,
        project_user
      )

    {show_github_setup, show_repo_setup, show_sync_button,
     project_repo_connection} = repo_settings(project)

    if show_repo_setup and connected?(socket) do
      collect_project_repo_connections(socket.assigns.project.id)
    end

    {:ok,
     socket
     |> assign(
       active_menu_item: :settings,
       webhook_auth_methods: auth_methods,
       credentials: credentials,
       project_users: project_users,
       current_user: socket.assigns.current_user,
       project_changeset: Projects.change_project(socket.assigns.project),
       can_delete_project: can_delete_project,
       can_edit_project: can_edit_project,
       can_edit_data_retention: can_edit_data_retention,
       can_write_webhook_auth_method: can_write_webhook_auth_method,
       can_create_project_credential: can_create_project_credential,
       show_github_setup: show_github_setup,
       show_repo_setup: show_repo_setup,
       show_sync_button: show_sync_button,
       project_repo_connection: project_repo_connection,
       repos: [],
       branches: [],
       loading_branches: false,
       github_enabled: VersionControl.github_enabled?(),
       can_install_github: can_write_github_connection,
       can_initiate_github_sync: can_initiate_github_sync,
       pending_github_installation:
         VersionControl.get_pending_user_installation(
           socket.assigns.current_user.id
         ),
       selected_credential_type: nil
     )}
  end

  defp repo_settings(%Project{id: project_id}) do
    repo_connection = VersionControl.get_repo_connection(project_id)

    project_repo_connection = %{"repo" => nil, "branch" => nil}

    # {show_github_setup, show_repo_setup, show_sync_button}
    case repo_connection do
      nil ->
        {true, false, false, project_repo_connection}

      %{repo: nil} ->
        {false, true, false, project_repo_connection}

      %{repo: r, branch: b, github_installation_id: g} ->
        {false, true, true,
         %{"repo" => r, "branch" => b, "github_installation_id" => g}}
    end
  end

  # we should only run this if repo setting is pending
  defp collect_project_repo_connections(project_id) do
    pid = self()

    Task.start(fn ->
      resp = VersionControl.fetch_installation_repos(project_id)
      send(pid, {:repos_fetched, resp})
    end)
  end

  defp can_edit_digest_alert(
         %User{} = current_user,
         %ProjectUser{} = project_user
       ),
       do:
         ProjectUsers
         |> Permissions.can?(:edit_digest_alerts, current_user, project_user)

  defp can_edit_failure_alert(
         %User{} = current_user,
         %ProjectUser{} = project_user
       ),
       do:
         ProjectUsers
         |> Permissions.can?(:edit_failure_alerts, current_user, project_user)

  defp can_edit_project(assigns), do: assigns.can_edit_project

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, socket |> apply_action(socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :index, _params) do
    socket |> assign(:page_title, "Project settings")
  end

  defp apply_action(socket, :delete, %{"project_id" => id}) do
    if socket.assigns.can_delete_project do
      socket |> assign(:page_title, "Project settings")
    else
      socket
      |> put_flash(:error, "You are not authorize to perform this action")
      |> push_patch(to: ~p"/projects/#{id}/settings")
    end
  end

  @impl true
  def handle_event("validate", %{"project" => project_params}, socket) do
    changeset =
      socket.assigns.project
      |> Projects.change_project(project_params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :project_changeset, changeset)}
  end

  # validate without input can be ignored
  def handle_event("validate", _params, socket) do
    {:noreply, socket}
  end

  def handle_event("cancel-retention-change", _params, socket) do
    {:noreply,
     socket
     |> assign(
       :project_changeset,
       Projects.change_project(socket.assigns.project)
     )}
  end

  def handle_event("save", %{"project" => project_params}, socket) do
    if can_edit_project(socket.assigns) do
      save_project(socket, project_params)
    else
      {:noreply,
       socket
       |> put_flash(:error, "You are not authorized to perform this action.")}
    end
  end

  def handle_event("toggle-mfa", _params, socket) do
    if can_edit_project(socket.assigns) do
      project = socket.assigns.project

      {:ok, project} =
        Projects.update_project(project, %{requires_mfa: !project.requires_mfa})

      {:noreply,
       socket
       |> assign(:project, project)
       |> put_flash(:info, "Project MFA requirement updated successfully")}
    else
      {:noreply,
       put_flash(
         socket,
         :error,
         "You are not authorized to perform this action."
       )}
    end
  end

  def handle_event(
        "set_failure_alert",
        %{
          "project_user_id" => project_user_id,
          "failure_alert" => failure_alert
        },
        socket
      ) do
    project_user = Projects.get_project_user!(project_user_id)

    changeset =
      {%{failure_alert: project_user.failure_alert}, %{failure_alert: :boolean}}
      |> Ecto.Changeset.cast(%{failure_alert: failure_alert}, [:failure_alert])

    case Ecto.Changeset.get_change(changeset, :failure_alert) do
      nil ->
        {:noreply, socket}

      setting ->
        Projects.update_project_user(project_user, %{failure_alert: setting})
        |> dispatch_flash(socket)
    end
  end

  def handle_event(
        "set_digest",
        %{"project_user_id" => project_user_id, "digest" => digest},
        socket
      ) do
    project_user = Projects.get_project_user!(project_user_id)

    changeset =
      {%{digest: project_user.digest |> to_string()}, %{digest: :string}}
      |> Ecto.Changeset.cast(%{digest: digest}, [:digest])

    case Ecto.Changeset.get_change(changeset, :digest) do
      nil ->
        {:noreply, socket}

      digest ->
        Projects.update_project_user(project_user, %{digest: digest})
        |> dispatch_flash(socket)
    end
  end

  def handle_event("install_app", _, socket) do
    user_id = socket.assigns.current_user.id
    project_id = socket.assigns.project.id

    case Application.get_env(:lightning, :github_app) |> Map.new() do
      %{app_name: nil} ->
        Logger.error("GitHub App Name not configured")
        # Send to sentry and show cozy error
        error =
          GithubError.misconfigured("GitHub App Name Misconfigured", %{
            app_name: nil
          })

        Sentry.capture_exception(error)

        {:noreply,
         socket
         |> put_flash(
           :error,
           "Sorry, it seems that the GitHub App Name has not been properly configured for this instance of Lighting. Please contact the instance administrator"
         )}

      %{app_name: app_name} ->
        {:ok, _connection} =
          VersionControl.create_github_connection(%{
            user_id: user_id,
            project_id: project_id
          })

        {:noreply,
         redirect(socket,
           external: "https://github.com/apps/#{app_name}"
         )}
    end
  end

  def handle_event("reinstall_app", _, socket) do
    user_id = socket.assigns.current_user.id
    project_id = socket.assigns.project.id

    case Application.get_env(:lightning, :github_app) |> Map.new() do
      %{app_name: nil} ->
        error =
          GithubError.misconfigured("GitHub App Name Misconfigured", %{
            app_name: nil
          })

        Sentry.capture_exception(error)

        {:noreply,
         socket
         |> put_flash(
           :error,
           "Sorry, it seems that the GitHub App Name has not been properly configured for this instance of Lighting. Please contact the instance administrator"
         )}

      %{app_name: app_name} ->
        {:ok, _} = VersionControl.remove_github_connection(project_id)

        {:ok, _connection} =
          VersionControl.create_github_connection(%{
            user_id: user_id,
            project_id: project_id
          })

        {:noreply,
         redirect(socket, external: "https://github.com/apps/#{app_name}")}
    end
  end

  def handle_event("delete_repo_connection", _, socket) do
    project_id = socket.assigns.project.id

    {:ok, _} = VersionControl.remove_github_connection(project_id)

    {:noreply,
     socket
     |> assign(show_github_setup: true, show_sync_button: false)
     |> push_patch(to: ~p"/projects/#{project_id}/settings#vcs")}
  end

  def handle_event("save_repo", params, socket) do
    %{project: project} = socket.assigns

    {:ok, %{github_installation_id: github_installation_id}} =
      VersionControl.add_github_repo_and_branch(
        project.id,
        params["repo"],
        params["branch"]
      )

    {:noreply,
     socket
     |> assign(
       show_repo_setup: false,
       show_sync_button: true,
       project_repo_connection: %{
         "branch" => params["branch"],
         "repo" => params["repo"],
         "github_installation_id" => github_installation_id
       }
     )}
  end

  def handle_event(
        "initiate_sync",
        params,
        %{assigns: %{current_user: u}} = socket
      ) do
    if socket.assigns.can_initiate_github_sync do
      case VersionControl.initiate_sync(params["id"], u.email) do
        {:ok, :fired} ->
          {:noreply, socket |> put_flash(:info, "Sync Initialized")}

        _err ->
          # we should log or instrument this situation
          {:noreply, socket |> put_flash(:error, "Sync Error")}
      end
    else
      {:noreply, socket |> put_flash(:error, "Viewers Cannot Initiate Sync")}
    end
  end

  def handle_event("repo_selected", params, socket) do
    pid = self()

    Task.start(fn ->
      {:ok, branches} =
        VersionControl.fetch_repo_branches(
          socket.assigns.project.id,
          params["repo"]
        )

      send(pid, {:branches_fetched, branches})
    end)

    {:noreply,
     socket
     |> assign(
       loading_branches: true,
       project_repo_connection: %{
         socket.assigns.project_repo_connection
         | "repo" => params["repo"]
       }
     )}
  end

  def handle_event("branch_selected", params, socket) do
    {:noreply,
     socket
     |> assign(
       project_repo_connection: %{
         socket.assigns.project_repo_connection
         | "branch" => params["branch"]
       }
     )}
  end

  @impl true
  def handle_info({:branches_fetched, branches_result}, socket) do
    case branches_result do
      {:error, error} ->
        {:noreply, socket |> put_flash(:error, error_message(error))}

      branches ->
        {:noreply, socket |> assign(loading_branches: false, branches: branches)}
    end
  end

  def handle_info({:forward, mod, opts}, socket) do
    send_update(mod, opts)
    {:noreply, socket}
  end

  def handle_info({:repos_fetched, result}, socket) do
    case result do
      {:error, error} ->
        {:noreply, socket |> put_flash(:error, error_message(error))}

      {:ok, [_ | _] = repos} ->
        {:noreply, socket |> assign(repos: repos)}

      # while it's possible to trigger this state when testing
      # GitHub makes it pretty impossible to arrive here
      _ ->
        {:noreply, socket}
    end
  end

  def handle_info({:credential_type_changed, type}, socket) do
    {:noreply, socket |> assign(:selected_credential_type, type)}
  end

  defp error_message(error) do
    case error do
      %{code: :installation_not_found} ->
        "Sorry, it seems that the GitHub App ID has not been properly configured for this instance of Lightning. Please contact the instance administrator"

      %{code: :invalid_certificate} ->
        "Sorry, it seems that the GitHub cert has not been properly configured for this instance of Lightning. Please contact the instance administrator"
    end
  end

  defp dispatch_flash(change_result, socket) do
    case change_result do
      {:ok, %ProjectUser{}} ->
        {:noreply,
         socket
         |> assign(
           :project_users,
           Projects.get_project_users!(socket.assigns.project.id)
         )
         |> put_flash(:info, "Project user updated successfuly")}

      {:error, %Ecto.Changeset{}} ->
        {:noreply,
         socket
         |> put_flash(:error, "Error when updating the project user")}
    end
  end

  def failure_alert(assigns) do
    assigns =
      assigns
      |> assign(
        can_edit_failure_alert:
          can_edit_failure_alert(assigns.current_user, assigns.project_user)
      )

    ~H"""
    <%= if @can_edit_failure_alert do %>
      <.form
        :let={form}
        for={%{"failure_alert" => @project_user.failure_alert}}
        phx-change="set_failure_alert"
        id={"failure-alert-#{@project_user.id}"}
      >
        <%= Phoenix.HTML.Form.hidden_input(form, :project_user_id,
          value: @project_user.id
        ) %>
        <LightningWeb.Components.Form.select_field
          form={form}
          name="failure_alert"
          values={[Disabled: false, Enabled: true]}
        />
      </.form>
    <% else %>
      <%= if @project_user.failure_alert,
        do: "Enabled",
        else: "Disabled" %>
    <% end %>
    """
  end

  def digest(assigns) do
    assigns =
      assigns
      |> assign(
        can_edit_digest_alert:
          can_edit_digest_alert(assigns.current_user, assigns.project_user)
      )

    ~H"""
    <%= if @can_edit_digest_alert do %>
      <.form
        :let={form}
        for={%{"digest" => @project_user.digest}}
        phx-change="set_digest"
        id={"digest-#{@project_user.id}"}
      >
        <%= Phoenix.HTML.Form.hidden_input(form, :project_user_id,
          value: @project_user.id
        ) %>
        <LightningWeb.Components.Form.select_field
          form={form}
          name="digest"
          values={[
            Never: "never",
            Daily: "daily",
            Weekly: "weekly",
            Monthly: "monthly"
          ]}
        />
      </.form>
    <% else %>
      <%= @project_user.digest
      |> Atom.to_string()
      |> String.capitalize() %>
    <% end %>
    """
  end

  def role(assigns) do
    ~H"""
    <%= @project_user.role |> Atom.to_string() |> String.capitalize() %>
    """
  end

  def user(assigns) do
    ~H"""
    <%= @project_user.user.first_name %> <%= @project_user.user.last_name %>
    """
  end

  defp checked?(changeset, input_id) do
    Ecto.Changeset.fetch_field!(changeset, :retention_policy) == input_id
  end

  defp save_project(socket, project_params) do
    case Projects.update_project(socket.assigns.project, project_params) do
      {:ok, project} ->
        {:noreply,
         socket
         |> assign(:project, project)
         |> put_flash(:info, "Project updated successfully")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :project_changeset, changeset)}
    end
  end

  def permissions_message(assigns) do
    ~H"""
    <small id="permission" class="mt-2 text-red-700">
      Role based permissions: You cannot modify this project's <%= @section %>
    </small>
    """
  end

  defp has_pending_installation?(%{id: project_id}, %{
         project_id: installation_project_id
       }) do
    project_id != installation_project_id
  end

  defp has_pending_installation?(_project, _installation) do
    false
  end

  defp install_github_tooltip(project, can_install_github, pending_installation) do
    case {can_install_github,
          has_pending_installation?(project, pending_installation)} do
      {false, _} ->
        "You're not allowed to configure repository connections for this project."

      {_, true} ->
        """
        You have a pending github installation in another project.
        <a href="#{~p"/projects/#{pending_installation.project_id}/settings#vcs"}" class="underline text-blue-400">Click here</a> to complete it / remove it before proceeding
        """

      _other ->
        nil
    end
  end
end
