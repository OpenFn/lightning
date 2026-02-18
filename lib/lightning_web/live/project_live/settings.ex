defmodule LightningWeb.ProjectLive.Settings do
  @moduledoc """
  Index Liveview for project settings
  """
  use LightningWeb, :live_view

  import LightningWeb.LayoutComponents

  alias Lightning.Collections
  alias Lightning.Credentials
  alias Lightning.Policies.Permissions
  alias Lightning.Projects
  alias Lightning.Projects.ProjectLimiter
  alias Lightning.Projects.ProjectUser
  alias Lightning.VersionControl
  alias Lightning.WebhookAuthMethods
  alias Lightning.Helpers
  alias LightningWeb.Components.GithubComponents

  require Logger

  on_mount {LightningWeb.Hooks, :project_scope}
  on_mount {LightningWeb.Hooks, :check_limits}
  on_mount {LightningWeb.Hooks, :limit_github_sync}
  on_mount {LightningWeb.Hooks, :limit_mfa}
  on_mount {LightningWeb.Hooks, :limit_retention_periods}

  @impl true
  def mount(_params, _session, socket) do
    %{project: project, current_user: current_user} = socket.assigns

    if connected?(socket) do
      VersionControl.subscribe(current_user)
    end

    project_user = Projects.get_project_user(project, current_user)

    project_files = Projects.list_project_files(project)
    collections = Collections.list_project_collections(project)

    projects = Projects.get_projects_for_user(current_user)

    permissions = %{
      can_delete_project:
        Permissions.can?(:project_users, :delete_project, current_user, project),
      can_edit_project:
        Permissions.can?(:project_users, :edit_project, current_user, project),
      can_add_project_user:
        Permissions.can?(
          :project_users,
          :add_project_user,
          current_user,
          project
        ),
      can_remove_project_user:
        Permissions.can?(
          :project_users,
          :remove_project_user,
          current_user,
          project
        ),
      can_edit_data_retention:
        Permissions.can?(
          :project_users,
          :edit_data_retention,
          current_user,
          project
        ),
      can_write_webhook_auth_method:
        Permissions.can?(
          :project_users,
          :write_webhook_auth_method,
          current_user,
          project
        ),
      can_install_github:
        Permissions.can?(
          :project_users,
          :write_github_connection,
          current_user,
          project
        ),
      can_initiate_github_sync:
        Permissions.can?(
          :project_users,
          :initiate_github_sync,
          current_user,
          project
        ),
      can_create_project_credential:
        Permissions.can?(
          :project_users,
          :create_project_credential,
          current_user,
          project
        ),
      can_create_keychain_credential:
        Permissions.can?(
          :credentials,
          :create_keychain_credential,
          current_user,
          %{project: project, project_user: project_user}
        ),
      can_create_collection:
        Permissions.can?(
          :project_users,
          :create_collection,
          current_user,
          project
        )
    }

    can_receive_failure_alerts =
      :ok == ProjectLimiter.limit_failure_alert(project.id)

    repo_connection = VersionControl.get_repo_connection_for_project(project.id)

    {:ok,
     socket
     |> assign(
       active_menu_item: :settings,
       can_receive_failure_alerts: can_receive_failure_alerts,
       collaborators_to_invite: [],
       collections: collections,
       current_user: socket.assigns.current_user,
       github_enabled: VersionControl.github_enabled?(),
       name: socket.assigns.project.name,
       project_changeset: Projects.change_project(socket.assigns.project),
       project_files: project_files,
       project_repo_connection: repo_connection,
       project_user: project_user,
       project_users: [],
       projects: projects,
       selected_credential_type: nil,
       show_collaborators_modal: false,
       show_invite_collaborators_modal: false,
       webhook_auth_methods: [],
       active_modal: nil,
       active_modal_assigns: nil
     )
     |> assign(permissions)}
  end

  @impl true
  def handle_params(params, _url, socket) do
    %{project: %{id: _project_id}, live_action: live_action} = socket.assigns

    {:noreply,
     socket
     |> apply_action(live_action, params)}
  end

  defp apply_action(socket, :index, _params) do
    project_users = Projects.get_project_users!(socket.assigns.project.id)
    auth_methods = WebhookAuthMethods.list_for_project(socket.assigns.project)

    concurrency_input_component =
      socket.router
      |> Phoenix.Router.route_info(
        "GET",
        ~p"/projects/:project_id/settings",
        nil
      )
      |> Map.get(:concurrency_input)

    socket
    |> assign(
      page_title: "Project settings",
      project_users: project_users,
      webhook_auth_methods: auth_methods,
      concurrency_input_component: concurrency_input_component,
      show_collaborators_modal: false,
      show_invite_collaborators_modal: false,
      active_modal: nil,
      active_modal_assigns: nil
    )
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
      params
      |> coerce_raw_name_to_safe_name()
      |> then(fn params ->
        if params["retention_policy"] == "erase_all" do
          Map.merge(params, %{"dataclip_retention_period" => nil})
        else
          params
        end
      end)

    changeset =
      socket.assigns.project
      |> Projects.change_project(params)
      |> Map.put(:action, :validate)

    {:noreply,
     socket
     |> assign(:project_changeset, changeset)
     |> assign(:name, Ecto.Changeset.fetch_field!(changeset, :name))}
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
    if socket.assigns.can_edit_project do
      save_project(socket, coerce_raw_name_to_safe_name(project_params))
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

  def handle_event("toggle_support_access", _params, socket) do
    if socket.assigns.can_edit_project do
      project = socket.assigns.project

      {:ok, project} =
        Projects.update_project(
          project,
          %{
            allow_support_access: !project.allow_support_access
          },
          socket.assigns.current_user
        )

      flash_msg =
        if project.allow_support_access do
          "Granted access to support users successfully"
        else
          "Revoked access to support users successfully"
        end

      {:noreply,
       socket
       |> assign(:project, project)
       |> put_flash(:info, flash_msg)}
    else
      {:noreply,
       put_flash(
         socket,
         :error,
         "You are not authorized to perform this action."
       )}
    end
  end

  def handle_event("toggle-mfa", _params, socket) do
    if socket.assigns.can_edit_project && socket.assigns.can_require_mfa do
      %{project: project, current_user: current_user} = socket.assigns

      {:ok, project} =
        Projects.update_project(
          project,
          %{requires_mfa: !project.requires_mfa},
          current_user
        )

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

  def handle_event("toggle_invite_collaborators_modal", _params, socket) do
    {:noreply,
     socket
     |> assign(
       :show_invite_collaborators_modal,
       !socket.assigns.show_invite_collaborators_modal
     )}
  end

  def handle_event("close_active_modal", _params, socket) do
    socket
    |> assign(active_modal: nil, active_modal_assigns: nil)
    |> noreply()
  end

  def handle_event(
        "show_modal",
        %{"target" => "new_webhook_auth_method"},
        socket
      ) do
    if socket.assigns.can_write_webhook_auth_method do
      socket
      |> assign(
        active_modal: :new_webhook_auth_method,
        active_modal_assigns: %{
          webhook_auth_method: %Lightning.Workflows.WebhookAuthMethod{
            project_id: socket.assigns.project.id
          }
        }
      )
      |> noreply()
    else
      socket
      |> put_flash(:error, "You are not authorized to perform this action")
      |> noreply()
    end
  end

  def handle_event(
        "show_modal",
        %{"target" => target_modal, "id" => auth_method_id},
        socket
      )
      when target_modal in [
             "edit_webhook_auth_method",
             "delete_webhook_auth_method"
           ] do
    if socket.assigns.can_write_webhook_auth_method do
      auth_method =
        WebhookAuthMethods.find_by_id!(auth_method_id, include: [:triggers])

      socket
      |> assign(
        active_modal: String.to_existing_atom(target_modal),
        active_modal_assigns: %{webhook_auth_method: auth_method}
      )
      |> noreply()
    else
      socket
      |> put_flash(:error, "You are not authorized to perform this action")
      |> noreply()
    end
  end

  def handle_event(
        "show_modal",
        %{
          "target" => "linked_triggers_for_webhook_auth_method",
          "id" => auth_method_id
        },
        socket
      ) do
    auth_method =
      WebhookAuthMethods.find_by_id!(auth_method_id,
        include: [triggers: [:workflow]]
      )

    socket
    |> assign(
      active_modal: :linked_triggers_for_webhook_auth_method,
      active_modal_assigns: %{webhook_auth_method: auth_method}
    )
    |> noreply()
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
       |> put_flash(:info, "Collaborator removed")
       |> push_navigate(
         to: ~p"/projects/#{assigns.project}/settings#collaboration"
       )}
    else
      {:noreply,
       socket
       |> put_flash(:error, "You are not authorized to perform this action")}
    end
  end

  @impl true
  def handle_info({:forward, mod, opts}, socket) do
    send_update(mod, opts)
    {:noreply, socket}
  end

  def handle_info(
        %Lightning.VersionControl.Events.OauthTokenAdded{},
        socket
      ) do
    {:noreply,
     socket
     |> put_flash(:info, "GitHub account linked successfully")
     |> push_navigate(to: ~p"/projects/#{socket.assigns.project}/settings#vcs")}
  end

  def handle_info(
        %Lightning.VersionControl.Events.OauthTokenFailed{},
        socket
      ) do
    {:noreply,
     socket
     |> put_flash(
       :error,
       "Oops! GitHub account failed to link. Please try again"
     )}
  end

  def handle_info({:show_invite_collaborators_modal, new_project_users}, socket) do
    {:noreply,
     socket
     |> assign(
       :show_invite_collaborators_modal,
       true
     )
     |> assign(:collaborators_to_invite, new_project_users)}
  end

  # catch all callback. Needed for tests because of Swoosh emails in tests
  def handle_info(msg, socket) do
    Logger.debug("Received unknown message: #{inspect(msg)}")
    {:noreply, socket}
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

  defp coerce_raw_name_to_safe_name(%{"raw_name" => raw_name} = params) do
    params |> Map.put("name", Helpers.url_safe_name(raw_name))
  end

  defp coerce_raw_name_to_safe_name(params), do: params

  defp checked?(changeset, input_id) do
    Ecto.Changeset.fetch_field!(changeset, :retention_policy) == input_id
  end

  defp save_project(socket, project_params) do
    socket.assigns.project
    |> Projects.update_project(project_params, socket.assigns.current_user)
    |> case do
      {:ok, project} ->
        {:noreply,
         socket
         |> assign(:project, project)
         |> put_flash(:info, "Project updated successfully")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :project_changeset, changeset)}

      {:error, :not_related_to_project} ->
        {:noreply,
         socket
         |> put_flash(:error, "Changes couldn't be saved, please try again")}
    end
  end

  defp confirm_user_removal_modal(assigns) do
    user_credentials =
      Credentials.list_user_credentials_in_project(
        assigns.project_user.user,
        assigns.project_user.project
      )

    {access_text, credentials_text} =
      case user_credentials do
        [] ->
          {"They will no longer have access to this project.", ""}

        [credential] ->
          {"They will no longer have access to this project",
           " and their owned credential #{credential.name} will be removed from it"}

        credentials ->
          credentials_list = Enum.map_join(credentials, ", ", & &1.name)

          {"They will no longer have access to this project",
           " and their owned credentials #{credentials_list} will be removed from it"}
      end

    assigns = assign(assigns, :access_text, access_text)
    assigns = assign(assigns, :credentials_text, credentials_text)

    ~H"""
    <.modal id={@id} width="max-w-md">
      <:title>
        <div class="flex justify-between">
          <span class="font-bold">
            Remove {@project_user.user.first_name} {@project_user.user.last_name}
          </span>

          <button
            phx-click={hide_modal(@id)}
            type="button"
            class="rounded-md bg-white text-gray-400 hover:text-gray-500 focus:outline-none"
            aria-label={gettext("close")}
          >
            <span class="sr-only">Close</span>
            <.icon name="hero-x-mark" class="h-5 w-5 stroke-current" />
          </button>
        </div>
      </:title>
      <div>
        <p class="text-sm text-gray-500">
          Are you sure you want to remove "{@project_user.user.first_name} {@project_user.user.last_name}" from this project? {@access_text}{@credentials_text}.
          <br /> Do you wish to proceed with this action?
        </p>
      </div>
      <.modal_footer>
        <.button
          id={"#{@id}_confirm_button"}
          type="button"
          phx-value-project_user_id={@project_user.id}
          phx-click="remove_project_user"
          theme="danger"
          phx-disable-with="Removing..."
        >
          Confirm
        </.button>
        <.button type="button" phx-click={hide_modal(@id)} theme="secondary">
          Cancel
        </.button>
      </.modal_footer>
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

  defp get_collaborator_limit_error(project) do
    case ProjectLimiter.request_new_user(project.id, 1) do
      :ok ->
        nil

      {:error, _reason, %{text: error}} ->
        error
    end
  end

  attr :can_edit_project, :boolean, required: true
  attr :project, :any, required: true

  def support_access_toggle(assigns) do
    ~H"""
    <div class="flex flex-row items-center mb-4">
      <div :if={@can_edit_project} class="flex flex-row">
        <div>
          <.input
            type="toggle"
            id="toggle-support-access"
            name="allow_support_access"
            checked={@project.allow_support_access}
            phx-click="toggle_support_access"
            label="Grant support access"
          />
        </div>
        <div>
          <Common.tooltip
            id="toggle-support-tooltip"
            title="Granting support access will allow all designated support users for this Lightning instance to access this project with editor permissions."
            class="inline-block"
          />
        </div>
      </div>
    </div>
    """
  end
end
