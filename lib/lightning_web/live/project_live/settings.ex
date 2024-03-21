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
  alias Lightning.Projects.ProjectUser
  alias Lightning.VersionControl
  alias Lightning.WebhookAuthMethods
  alias Lightning.Workflows.WebhookAuthMethod
  alias LightningWeb.Components.Form
  alias LightningWeb.Components.GithubComponents
  alias LightningWeb.LiveHelpers

  require Logger

  on_mount {LightningWeb.Hooks, :project_scope}

  @impl true
  def mount(_params, _session, socket) do
    %{project: project, current_user: current_user} = socket.assigns

    project_users =
      Projects.get_project_users!(project.id)

    project_user =
      Enum.find(project_users, fn project_user ->
        project_user.user_id == current_user.id
      end)

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
        project_user
      )

    can_add_project_user =
      Permissions.can?(
        ProjectUsers,
        :add_project_user,
        current_user,
        project_user
      )

    can_remove_project_user =
      Permissions.can?(
        ProjectUsers,
        :remove_project_user,
        current_user,
        project_user
      )

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

    repo_connection = VersionControl.get_repo_connection(project.id)

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
       can_add_project_user: can_add_project_user,
       can_remove_project_user: can_remove_project_user,
       can_edit_data_retention: can_edit_data_retention,
       can_write_webhook_auth_method: can_write_webhook_auth_method,
       can_create_project_credential: can_create_project_credential,
       project_repo_connection: repo_connection,
       github_enabled: VersionControl.github_enabled?(),
       can_install_github: can_write_github_connection,
       can_initiate_github_sync: can_initiate_github_sync,
       selected_credential_type: nil,
       show_collaborators_modal: false
     )}
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
    %{project: %{id: project_id}, live_action: live_action} = socket.assigns

    {:noreply,
     socket
     |> LiveHelpers.check_limits(project_id)
     |> apply_action(live_action, params)}
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
  def handle_event("validate", %{"project" => params}, socket) do
    params =
      if params["retention_policy"] == "erase_all" do
        Map.merge(params, %{"dataclip_retention_period" => nil})
      else
        params
      end

    changeset =
      socket.assigns.project
      |> Projects.change_project(params)
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

  def handle_event(
        "save_retention_settings",
        %{"project" => project_params},
        socket
      ) do
    if socket.assigns.can_edit_data_retention do
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

  def handle_event("toggle_collaborators_modal", _params, socket) do
    {:noreply,
     socket
     |> assign(
       :show_collaborators_modal,
       !socket.assigns.show_collaborators_modal
     )}
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

  def handle_event(
        "remove_project_user",
        %{"project_user_id" => project_user_id},
        %{assigns: assigns} = socket
      ) do
    project_user = Projects.get_project_user!(project_user_id)

    if user_removable?(
         project_user,
         assigns.current_user,
         assigns.can_remove_project_user
       ) do
      Projects.delete_project_user!(project_user)

      {:noreply,
       socket
       |> put_flash(:info, "Collaborator removed successfully!")
       |> assign(
         :project_users,
         Projects.get_project_users!(assigns.project.id)
       )}
    else
      {:noreply,
       socket
       |> put_flash(:error, "You are not authorized to perform this action")}
    end
  end

  @impl true
  def handle_info(:collaborators_updated, socket) do
    project_users =
      Projects.get_project_users!(socket.assigns.project.id)

    {:noreply,
     socket
     |> assign(project_users: project_users, show_collaborators_modal: false)
     |> put_flash(:info, "Collaborators updated successfully!")}
  end

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

  # catch all callback. Needed for tests because of Swoosh emails in tests
  def handle_info(msg, socket) do
    Logger.debug("Received unknown message: #{inspect(msg)}")
    {:noreply, socket}
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
    <div>
      <%= @project_user.user.first_name %> <%= @project_user.user.last_name %>
    </div>
    <span class="text-xs"><%= @project_user.user.email %></span>
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

  defp confirm_user_removal_modal(assigns) do
    ~H"""
    <.modal id={@id} width="max-w-md">
      <:title>
        <div class="flex justify-between">
          <span class="font-bold">
            Remove <%= @project_user.user.first_name %> <%= @project_user.user.last_name %>
          </span>

          <button
            phx-click={hide_modal(@id)}
            type="button"
            class="rounded-md bg-white text-gray-400 hover:text-gray-500 focus:outline-none"
            aria-label={gettext("close")}
          >
            <span class="sr-only">Close</span>
            <Heroicons.x_mark solid class="h-5 w-5 stroke-current" />
          </button>
        </div>
      </:title>
      <div class="px-6">
        <p class="text-sm text-gray-500">
          Are you sure you want to remove "<%= @project_user.user.first_name %> <%= @project_user.user.last_name %>" from this project?
          They will nolonger have access.
          Do you wish to proceed with this action?
        </p>
      </div>
      <div class="flex flex-row-reverse gap-4 mx-6 mt-2">
        <.button
          id={"#{@id}_confirm_button"}
          type="button"
          phx-value-project_user_id={@project_user.id}
          phx-click="remove_project_user"
          color_class="bg-red-600 hover:bg-red-700 text-white"
          phx-disable-with="Removing..."
        >
          Confirm
        </.button>
        <button
          type="button"
          phx-click={hide_modal(@id)}
          class="inline-flex items-center rounded-md bg-white px-3.5 py-2.5 text-sm font-semibold text-gray-900 shadow-sm ring-1 ring-inset ring-gray-300 hover:bg-gray-50"
        >
          Cancel
        </button>
      </div>
    </.modal>
    """
  end

  defp remove_user_tooltip(project_user, current_user, can_remove_project_user) do
    cond do
      !can_remove_project_user ->
        "You do not have permission to remove a user"

      project_user.user_id == current_user.id ->
        "You cannot remove yourself"

      project_user.role == :owner ->
        "You cannot remove an owner"

      true ->
        ""
    end
  end

  defp user_removable?(project_user, current_user, can_remove_project_user) do
    can_remove_project_user and project_user.role != :owner and
      project_user.user_id != current_user.id
  end

  defp user_has_valid_oauth_token(user) do
    VersionControl.oauth_token_valid?(user.github_oauth_token)
  end
end
