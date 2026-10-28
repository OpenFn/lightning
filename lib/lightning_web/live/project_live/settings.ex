defmodule LightningWeb.ProjectLive.Settings do
  @moduledoc """
  Index LiveView for project settings.

  ## View-extension slots

  Two slots let downstream apps inject LiveComponents into the settings page
  by registering them in route metadata:

      {"/projects/:project_id/settings", LightningWeb.ProjectLive.Settings, :index,
       metadata: %{
         concurrency_input: MyApp.ConcurrencyInputComponent,
         usage_caps_input: MyApp.UsageCapsInputComponent
       }}

  Each slot has its own assigns contract, which the component must accept:

    * `:concurrency_input` receives `field` (the `Ecto.Changeset` field for
      `project.concurrency`), `project`, and `disabled` (a pre-computed
      boolean — Lightning resolves whether the current user is allowed to
      edit the value and passes the result through).

    * `:usage_caps_input` receives `project` and `current_user`. The
      component computes its own permission gate (typically via
      `Lightning.Projects.Sandboxes.parent_admin?/2`) because cap-editing
      authority is owned by the downstream billing layer, not by Lightning.

  Slots are optional. Routes that omit a metadata key get a hidden slot —
  the page renders identically to OSS defaults.
  """
  use LightningWeb, :live_view

  alias Lightning.Accounts
  alias Lightning.Accounts.User
  alias Lightning.Collections
  alias Lightning.Collections.Collection
  alias Lightning.Credentials
  alias Lightning.Credentials.KeychainCredential
  alias Lightning.Helpers
  alias Lightning.Policies.Permissions
  alias Lightning.Projects
  alias Lightning.Projects.Project
  alias Lightning.Projects.ProjectLimiter
  alias Lightning.Projects.Sandboxes
  alias Lightning.VersionControl
  alias Lightning.VersionControl.ProjectRepoConnection
  alias Lightning.WebhookAuthMethods
  alias Lightning.Workflows.WebhookAuthMethod
  alias LightningWeb.Components.GithubComponents
  alias LightningWeb.CredentialLive.CredentialIndex
  alias LightningWeb.ProjectLive.Collaborators
  alias LightningWeb.ProjectLive.GithubSyncComponent
  alias LightningWeb.ProjectLive.InvitedCollaborators
  alias LightningWeb.ProjectLive.NewCollaboratorComponent

  require Logger

  on_mount {LightningWeb.Hooks, :project_scope}
  on_mount {LightningWeb.Hooks, :check_limits}
  on_mount {LightningWeb.Hooks, :limit_github_sync}
  on_mount {LightningWeb.Hooks, :limit_mfa}
  on_mount {LightningWeb.Hooks, :limit_retention_periods}

  attr :component, :atom, required: true
  attr :field, Phoenix.HTML.FormField, required: true
  attr :project, Project, required: true
  attr :disabled, :boolean, required: true

  @doc """
  View-extension slot wrapper for the project-level concurrency override input.
  Forwards `field`, `project`, and a pre-computed `disabled` boolean to the
  registered LiveComponent.
  """
  def concurrency_input_slot(assigns) do
    ~H"""
    <.live_component
      module={@component}
      id="concurrency-input-component"
      field={@field}
      project={@project}
      disabled={@disabled}
    />
    """
  end

  attr :component, :atom, required: true
  attr :project, Project, required: true
  attr :current_user, User, required: true

  @doc """
  View-extension slot wrapper for the per-project usage-caps input. Forwards
  `project` and `current_user` to the registered LiveComponent so the
  component can run its own permission gate (cap-editing authority lives in
  the downstream billing layer, not in Lightning).
  """
  def usage_caps_input_slot(assigns) do
    ~H"""
    <.live_component
      module={@component}
      id="usage-caps-input-component"
      project={@project}
      current_user={@current_user}
    />
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    %{project: project, current_user: current_user} = socket.assigns

    if connected?(socket) do
      VersionControl.subscribe(current_user)
    end

    project = Lightning.Repo.preload(project, :parent)
    sandbox? = Project.sandbox?(project)
    parent_project = if sandbox?, do: project.parent
    root_project = if sandbox?, do: Projects.root_of(project)

    project_user = Projects.get_project_user(project, current_user)

    project_files = Projects.list_project_files(project)

    # A new credential is shared with this project, so it is listed even when
    # it is a sandbox (the user's own list holds top-level projects only).
    projects =
      Enum.uniq_by(
        Projects.get_projects_for_user(current_user) ++ [project],
        & &1.id
      )

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
          project
        ),
      can_create_collection:
        Permissions.can?(
          :collections,
          :manage_collection,
          current_user,
          project
        )
    }

    can_receive_failure_alerts =
      :ok == ProjectLimiter.limit_failure_alert(project.id)

    repo_connection = VersionControl.get_repo_connection_for_project(project.id)

    route_metadata =
      Phoenix.Router.route_info(
        socket.router,
        "GET",
        ~p"/projects/:project_id/settings",
        nil
      )

    concurrency_input = Map.get(route_metadata, :concurrency_input)

    {:ok,
     socket
     |> assign(
       active_menu_item: :settings,
       can_receive_failure_alerts: can_receive_failure_alerts,
       current_user: socket.assigns.current_user,
       # github_enabled? answers with the last setting, not a boolean.
       github_enabled: VersionControl.github_enabled?() not in [nil, false],
       name: project.name,
       parent_project: parent_project,
       root_project: root_project,
       project: project,
       project_changeset:
         Project.form_changeset(project, %{raw_name: project.name}),
       project_files: project_files,
       project_repo_connection: repo_connection,
       project_user: project_user,
       project_users: [],
       projects: projects,
       sandbox?: sandbox?,
       selected_credential_type: nil,
       webhook_auth_methods: [],
       # The key `generate_api_key` last handed out, for the method created next.
       pending_api_key: nil,
       # The page draws the default concurrency switch itself; any other
       # input an instance configures is drawn beside it.
       hosted_concurrency_input:
         if(
           concurrency_input !=
             LightningWeb.ProjectLive.ConcurrencyInputComponent,
           do: concurrency_input
         ),
       usage_caps_input_component: Map.get(route_metadata, :usage_caps_input)
     )
     |> assign(permissions)
     |> CredentialIndex.assign_index()
     |> assign_page_data()}
  end

  @impl true
  def handle_params(params, _url, socket) do
    %{project: %{id: _project_id}, live_action: live_action} = socket.assigns

    {:noreply,
     socket
     |> apply_action(live_action, params)}
  end

  defp apply_action(socket, :index, _params) do
    assign(socket, page_title: "Project settings", deleting: false)
  end

  defp apply_action(socket, :delete, %{"project_id" => id}) do
    if socket.assigns.can_delete_project do
      assign(socket, page_title: "Project settings", deleting: true)
    else
      socket
      |> assign(page_title: "Project settings", deleting: false)
      |> put_flash(:error, "You are not authorize to perform this action")
      |> push_patch(to: ~p"/projects/#{id}/settings")
    end
  end

  @impl true
  def handle_event("validate", %{"project" => params}, socket) do
    # The retention and concurrency forms don't include raw_name,
    # so default to the project's current name for form_changeset.
    params =
      params
      |> Map.put_new("raw_name", socket.assigns.project.name)
      |> then(fn p ->
        if p["retention_policy"] == "erase_all" do
          Map.put(p, "dataclip_retention_period", nil)
        else
          p
        end
      end)

    changeset =
      socket.assigns.project
      |> Project.form_changeset(params)
      |> Helpers.copy_error(:name, :raw_name)
      |> Map.put(:action, :validate)

    {:noreply,
     socket
     |> assign(:project_changeset, changeset)
     |> assign(:name, Ecto.Changeset.get_field(changeset, :name))}
  end

  # validate without input can be ignored
  def handle_event("validate", _params, socket) do
    {:noreply, socket}
  end

  # What a refusal says when the instance's limit message is a component only.
  @limited "This action is limited for this project."

  # Fields the generic settings/concurrency save may set; gated by
  # `can_edit_project`. Privileged fields (requires_mfa, scheduled_deletion,
  # retention, allow_support_access, parent_id) are deliberately excluded so a
  # crafted payload cannot set them past their own dedicated gates.
  @project_settings_fields ~w(raw_name name description concurrency color)

  def handle_event("save", %{"project" => project_params}, socket) do
    case authorize(socket, :edit_project) do
      :ok ->
        params =
          project_params
          |> Helpers.derive_name_param()
          |> Map.take(@project_settings_fields)

        save_project(socket, params)

      {:error, :unauthorized} ->
        deny_action(socket, "save")
    end
  end

  # Support access is set to the value asked for, not flipped.
  def handle_event("set_support_access", %{"on" => on}, socket)
      when is_boolean(on) do
    with :ok <- authorize_reply(socket, :edit_project) do
      save_reply(
        %{allow_support_access: on},
        socket,
        if(on,
          do: "Granted access to support users successfully",
          else: "Revoked access to support users successfully"
        )
      )
    end
  end

  # MFA is set to the value asked for, not flipped. `can_require_mfa` comes
  # from the `:limit_mfa` hook: a usage limit, not a role.
  def handle_event("set_requires_mfa", %{"on" => on}, socket)
      when is_boolean(on) do
    with :ok <- authorize_reply(socket, :edit_project) do
      if socket.assigns.can_require_mfa do
        save_reply(
          %{requires_mfa: on},
          socket,
          "Project MFA requirement updated successfully"
        )
      else
        refuse_reply(socket, "set_requires_mfa", nil)
      end
    end
  end

  # Only the retention fields sent; erasing all keeps no input/output period.
  def handle_event("save_data_storage", params, socket) when is_map(params) do
    with :ok <- authorize_reply(socket, :edit_data_retention) do
      attrs =
        for {key, field} <- [
              {"historyRetentionPeriod", :history_retention_period},
              {"dataclipRetentionPeriod", :dataclip_retention_period},
              {"retentionPolicy", :retention_policy}
            ],
            Map.has_key?(params, key),
            into: %{},
            do: {field, params[key]}

      attrs
      |> then(fn
        %{retention_policy: "erase_all"} = attrs ->
          Map.put(attrs, :dataclip_retention_period, nil)

        attrs ->
          attrs
      end)
      |> save_reply(socket)
    end
  end

  def handle_event("sync_github", _params, socket) do
    with :ok <- authorize_reply(socket, :initiate_github_sync),
         {:ok, connection} <- project_repo_connection(socket) do
      message =
        "user #{socket.assigns.current_user.email} initiated a sync from Lightning"

      case VersionControl.initiate_sync(connection, message) do
        :ok ->
          socket |> put_flash(:info, "GitHub sync initiated") |> reply_ok()

        {:error, error} ->
          reply_error(
            socket,
            GithubSyncComponent.error_message(error) || @limited
          )
      end
    end
  end

  def handle_event("remove_github_connection", _params, socket) do
    with :ok <- authorize_reply(socket, :write_github_connection),
         {:ok, connection} <- project_repo_connection(socket) do
      {:ok, _} =
        VersionControl.remove_github_connection(
          connection,
          socket.assigns.current_user
        )

      socket
      |> assign(:project_repo_connection, nil)
      |> put_flash(:info, "Connection removed successfully")
      |> reply_ok()
    end
  end

  # Project Identity: the name as typed and the description, nothing else.
  def handle_event("save_identity", params, socket) when is_map(params) do
    with :ok <- authorize_reply(socket, :edit_project) do
      %{
        "raw_name" => params["rawName"],
        "description" => params["description"]
      }
      |> Map.reject(fn {_key, value} -> is_nil(value) end)
      |> Helpers.derive_name_param()
      |> save_reply(socket)
    end
  end

  # Concurrency Override: 1 for one run at a time, nil for parallel.
  def handle_event("save_concurrency", params, socket) when is_map(params) do
    with :ok <- authorize_reply(socket, :edit_project) do
      save_reply(%{"concurrency" => params["concurrency"]}, socket)
    end
  end

  # The deletion modal's one action, on the project read again now. A
  # sandbox is deleted with its children, as before; a project is
  # scheduled for deletion, or purged when it already is. The typed name is
  # checked against the project's own.
  def handle_event("delete_project", params, socket) when is_map(params) do
    typed =
      if is_binary(params["nameConfirmation"]),
        do: params["nameConfirmation"],
        else: ""

    with :ok <- authorize_reply(socket, :delete_project),
         %Project{} = project <-
           Projects.get_project(socket.assigns.project.id) ||
             reply_error(socket, "Project not found") do
      if Project.sandbox?(project),
        do: delete_sandbox(socket, project, typed),
        else: delete_project(socket, project, typed)
    end
  end

  # Keychains: the context asks the policy about the keychain, and an edit
  # or deletion finds it among this project's own.
  def handle_event("create_keychain_credential", params, socket)
      when is_map(params) do
    %{project: project, current_user: user} = socket.assigns

    %KeychainCredential{project_id: project.id, created_by_id: user.id}
    |> Credentials.create_keychain_credential(keychain_attrs(params), user)
    |> changed_reply(socket, "Keychain credential created successfully")
  end

  def handle_event("update_keychain_credential", %{"id" => id} = params, socket) do
    with {:ok, keychain} <- project_keychain(socket, id) do
      keychain
      |> Credentials.update_keychain_credential(
        keychain_attrs(params),
        socket.assigns.current_user
      )
      |> changed_reply(socket, "Keychain credential updated successfully")
    end
  end

  def handle_event("delete_keychain_credential", %{"id" => id}, socket) do
    with {:ok, keychain} <- project_keychain(socket, id) do
      keychain
      |> Credentials.delete_keychain_credential(socket.assigns.current_user)
      |> changed_reply(socket, "Keychain credential deleted")
    end
  end

  # Collections: found by id among this project's own, and only the name
  # changes.
  def handle_event("create_collection", params, socket) when is_map(params) do
    with :ok <- authorize_reply(socket, :manage_collection, :collections) do
      %{
        "project_id" => socket.assigns.project.id,
        "name" => collection_name(params)
      }
      |> Collections.create_collection()
      |> changed_reply(socket, "Collection created")
    end
  end

  def handle_event("rename_collection", %{"id" => id} = params, socket) do
    with {:ok, collection} <- project_collection(socket, id),
         :ok <-
           authorize_reply(socket, :manage_collection, :collections, collection) do
      collection
      |> Collections.update_collection(%{"name" => collection_name(params)})
      |> changed_reply(socket, "Collection updated")
    end
  end

  def handle_event("delete_collection", %{"id" => id}, socket) do
    with {:ok, collection} <- project_collection(socket, id),
         :ok <-
           authorize_reply(socket, :manage_collection, :collections, collection) do
      case Collections.delete_collection(collection.id) do
        {:ok, _collection} = deleted ->
          changed_reply(deleted, socket, "Collection deleted")

        {:error, _reason} ->
          reply_error(socket, "Couldn't delete collection!")
      end
    end
  end

  # The first item, as the old preview showed it.
  def handle_event("preview_collection", %{"id" => id}, socket) do
    with {:ok, collection} <- project_collection(socket, id),
         :ok <-
           authorize_reply(socket, :access_collection, :collections, collection) do
      record =
        case Collections.get_all(collection, limit: 1, cursor: nil) do
          [] ->
            nil

          [item | _] ->
            Jason.encode!(
              [
                %{
                  key: item.key,
                  value: item.value,
                  created: item.inserted_at,
                  updated: item.updated_at
                }
              ],
              pretty: true
            )
        end

      {:reply, %{record: record}, socket}
    end
  end

  # Webhook auth methods: each action asks the policy again, and a rename,
  # deletion or reveal finds the method among this project's own.
  def handle_event("generate_api_key", _params, socket) do
    with :ok <- authorize_webhook_reply(socket) do
      api_key = WebhookAuthMethod.generate_api_key()
      {:reply, %{apiKey: api_key}, assign(socket, :pending_api_key, api_key)}
    end
  end

  def handle_event("create_webhook_auth_method", params, socket)
      when is_map(params) do
    with :ok <- authorize_webhook_reply(socket) do
      params
      |> auth_method_attrs(socket)
      |> WebhookAuthMethods.create_auth_method(
        actor: socket.assigns.current_user
      )
      |> case do
        {:ok, _auth_method} = created ->
          changed_reply(
            created,
            assign(socket, :pending_api_key, nil),
            "Webhook auth method created successfully"
          )

        error ->
          changed_reply(error, socket, nil)
      end
    end
  end

  def handle_event("rename_webhook_auth_method", %{"id" => id} = params, socket) do
    with :ok <- authorize_webhook_reply(socket),
         {:ok, auth_method} <- project_auth_method(socket, id) do
      auth_method
      |> WebhookAuthMethods.update_auth_method(%{"name" => params["name"]},
        actor: socket.assigns.current_user
      )
      |> changed_reply(socket, "Webhook auth method updated successfully")
    end
  end

  def handle_event("delete_webhook_auth_method", %{"id" => id}, socket) do
    with :ok <- authorize_webhook_reply(socket),
         {:ok, auth_method} <- project_auth_method(socket, id) do
      auth_method
      |> WebhookAuthMethods.schedule_for_deletion(
        actor: socket.assigns.current_user
      )
      |> changed_reply(
        socket,
        "Your Webhook Authentication method has been deleted."
      )
    end
  end

  # The secret, only in this reply, once the user's password or code checks.
  def handle_event("reveal_webhook_secret", %{"id" => id} = params, socket) do
    with :ok <- authorize_webhook_reply(socket),
         {:ok, auth_method} <- project_auth_method(socket, id) do
      user = socket.assigns.current_user

      if Accounts.User.valid_password?(user, params["password"]) ||
           Accounts.valid_user_totp?(user, params["code"]) do
        secret =
          if auth_method.auth_type == :basic,
            do: auth_method.password,
            else: auth_method.api_key

        {:reply, %{secret: secret}, socket}
      else
        reply_error(socket, "Invalid! Please try again")
      end
    end
  end

  # Adds the emails that have accounts, and answers with the rest to invite.
  # The form shows one message, so a row's error is replied as the message.
  def handle_event("add_collaborators", %{"collaborators" => rows}, socket)
      when is_list(rows) do
    %{project: project, current_user: user} = socket.assigns

    with :ok <- authorize_reply(socket, :add_project_user),
         :ok <- limit_reply(socket, length(rows)),
         {:ok, collaborators} <-
           Collaborators.prepare_for_insertion(
             %Collaborators{},
             %{"collaborators" => rows},
             socket.assigns.project_users
           ),
         {existing, new} = Enum.split_with(collaborators, & &1.user_id),
         {:ok, _project_users} <-
           Projects.add_project_users(
             project,
             Enum.map(existing, &Map.take(&1, [:user_id, :role])),
             user
           ) do
      socket =
        socket
        |> assign_page_data()
        |> put_flash(
          :info,
          NewCollaboratorComponent.generate_flash_message(existing, new)
        )

      {:reply, %{toInvite: Enum.map(new, &%{email: &1.email, role: &1.role})},
       socket}
    else
      {:error, %Ecto.Changeset{} = changeset} ->
        reply_error(
          socket,
          changeset |> field_errors() |> Map.values() |> List.flatten() |> hd()
        )

      reply ->
        reply
    end
  end

  def handle_event("invite_collaborators", %{"collaborators" => rows}, socket)
      when is_list(rows) do
    %{project: project, current_user: user} = socket.assigns
    params = %{"invited_collaborators" => Enum.map(rows, &invite_params/1)}

    with :ok <- authorize_reply(socket, :add_project_user),
         :ok <- limit_reply(socket, length(rows)),
         {:ok, collaborators} <-
           InvitedCollaborators.validate_collaborators(
             %InvitedCollaborators{},
             params
           ) do
      project
      |> Projects.invite_collaborators(collaborators, user)
      |> changed_reply(
        socket,
        "Invite#{if length(collaborators) > 1, do: "s"} sent successfully"
      )
    else
      {:error, %Ecto.Changeset{} = changeset} -> reply_error(socket, changeset)
      reply -> reply
    end
  end

  def handle_event("remove_collaborator", %{"id" => id}, socket) do
    %{assigns: assigns} = socket

    project_user =
      Projects.get_project_user_for_project(id, assigns.project, include: :user)

    # Re-resolve the actor's own permission rather than trusting the
    # mount-time `:can_remove_project_user` assign - see `authorize/2`.
    if project_user &&
         user_removable?(
           project_user,
           assigns.current_user,
           :ok == authorize(socket, :remove_project_user),
           assigns.project,
           assigns.sandbox?
         ) do
      Projects.delete_project_user!(project_user, assigns.current_user)

      # Their credentials leave the project with them.
      changed_reply(
        {:ok, project_user},
        CredentialIndex.assign_index(socket),
        "Collaborator removed"
      )
    else
      refuse_reply(socket, "remove_collaborator", id)
    end
  end

  # Notification prefs (failure alerts, digest) are edited through one path,
  # each with a self-only policy action and the param that carries its value.
  @notification_prefs %{
    "set_failure_alert" => {:failure_alert, :edit_failure_alerts, "on"},
    "set_digest" => {:digest, :edit_digest_alerts, "digest"}
  }

  def handle_event(event, %{"id" => id} = params, socket)
      when is_map_key(@notification_prefs, event) do
    {field, action, key} = Map.fetch!(@notification_prefs, event)

    project_user =
      Projects.get_project_user_for_project(id, socket.assigns.project)

    if editable_alert_target?(action, project_user, socket) do
      case Projects.set_notification_pref(project_user, field, params[key]) do
        :unchanged ->
          reply_ok(socket)

        {:ok, _project_user} = updated ->
          changed_reply(updated, socket, "Project user updated successfuly")

        {:error, _changeset} ->
          reply_error(socket, "Error when updating the project user")
      end
    else
      refuse_reply(socket, event, id)
    end
  end

  # The Credentials tab's events, as on the user's Credentials page. One the
  # page doesn't send is refused there.
  def handle_event(event, params, socket),
    do: CredentialIndex.handle_event(event, params, socket)

  @impl true
  def handle_async(name, result, socket),
    do: CredentialIndex.handle_async(name, result, socket)

  @impl true
  def handle_info({:forward, CredentialIndex, _answer} = message, socket),
    do: CredentialIndex.handle_info(message, socket)

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

  # catch all callback. Needed for tests because of Swoosh emails in tests
  def handle_info(msg, socket) do
    Logger.debug("Received unknown message: #{inspect(msg)}")
    {:noreply, socket}
  end

  defp authorize(
         %{assigns: %{current_user: current_user, project: project}},
         action
       ) do
    Permissions.can(:project_users, action, current_user, project)
  end

  defp deny_action(socket, event, project_user_id \\ nil) do
    log_refusal(socket, event, project_user_id)

    {:noreply,
     put_flash(socket, :error, "You are not authorized to perform this action.")}
  end

  defp refuse_reply(socket, event, project_user_id) do
    log_refusal(socket, event, project_user_id)
    reply_error(socket, "You are not authorized to perform this action.")
  end

  defp log_refusal(socket, event, project_user_id) do
    %{project: project, current_user: current_user} = socket.assigns

    reason =
      if project_user_id,
        do:
          "project_user_id=#{inspect(project_user_id)} not in project, or " <>
            "not permitted for user=#{current_user.id}",
        else: "not permitted for user=#{current_user.id}"

    Logger.warning("Rejected #{event} in project=#{project.id}: #{reason}")
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
        changeset = Helpers.copy_error(changeset, :name, :raw_name)
        {:noreply, assign(socket, :project_changeset, changeset)}

      {:error, :not_related_to_project} ->
        {:noreply,
         socket
         |> put_flash(:error, "Changes couldn't be saved, please try again")}
    end
  end

  defp reply_ok(socket), do: {:reply, %{}, socket}

  # Every action asks the policy again, whatever the page showed: about the
  # project, or the record given.
  defp authorize_reply(socket, action, policy \\ :project_users, resource \\ nil) do
    %{project: project, current_user: current_user} = socket.assigns

    case Permissions.can(policy, action, current_user, resource || project) do
      :ok ->
        :ok

      {:error, :unauthorized} ->
        Logger.warning(
          "Rejected #{action} in project=#{project.id}: " <>
            "not permitted for user=#{current_user.id}"
        )

        reply_error(socket, "You are not authorized to perform this action.")
    end
  end

  # A sandbox uses its parent's webhook auth methods, managed from the parent.
  defp authorize_webhook_reply(socket) do
    if socket.assigns.sandbox?,
      do: reply_error(socket, "You are not authorized to perform this action."),
      else: authorize_reply(socket, :write_webhook_auth_method)
  end

  defp save_reply(attrs, socket, message \\ "Project updated successfully") do
    socket.assigns.project
    |> Projects.update_project(attrs, socket.assigns.current_user)
    |> case do
      {:ok, project} ->
        socket
        |> assign(:project, project)
        |> assign(:project_changeset, Project.form_changeset(project, %{}))
        |> put_flash(:info, message)
        |> reply_ok()

      {:error, %Ecto.Changeset{} = changeset} ->
        reply_error(socket, Helpers.copy_error(changeset, :name, :raw_name))

      {:error, :not_related_to_project} ->
        reply_error(socket, "Changes couldn't be saved, please try again")
    end
  end

  defp keychain_attrs(params) do
    %{
      "name" => params["name"],
      "path" => params["path"],
      "default_credential_id" => params["defaultCredentialId"]
    }
  end

  defp project_keychain(socket, id) do
    case Enum.find(
           Credentials.list_keychain_credentials_for_project(
             socket.assigns.project
           ),
           &(&1.id == id)
         ) do
      nil ->
        reply_error(socket, "You are not authorized to perform this action.")

      keychain ->
        {:ok, keychain}
    end
  end

  # A basic method's username is cleaned as the old form showed it; an API
  # key method gets the key last handed out (or a new one, when none was).
  defp auth_method_attrs(%{"authType" => "api"} = params, socket) do
    %{
      "auth_type" => "api",
      "name" => params["name"],
      "api_key" => socket.assigns.pending_api_key,
      "project_id" => socket.assigns.project.id
    }
  end

  defp auth_method_attrs(params, socket) do
    %{
      "auth_type" => params["authType"],
      "name" => params["name"],
      "username" =>
        if(is_binary(params["username"]),
          do: params["username"] |> String.downcase() |> String.replace(" ", "-")
        ),
      "password" => params["password"],
      "project_id" => socket.assigns.project.id
    }
  end

  # The project's connection read again, not the one the page was drawn with.
  defp project_repo_connection(socket) do
    case VersionControl.get_repo_connection_for_project(
           socket.assigns.project.id
         ) do
      nil -> reply_error(socket, "GitHub connection not found")
      connection -> {:ok, connection}
    end
  end

  defp project_auth_method(socket, id) do
    case WebhookAuthMethods.find_for_project(socket.assigns.project, id) do
      nil -> reply_error(socket, "Webhook auth method not found")
      auth_method -> {:ok, auth_method}
    end
  end

  defp invite_params(%{} = row) do
    %{
      "first_name" => row["firstName"],
      "last_name" => row["lastName"],
      "email" => row["email"],
      "role" => row["role"]
    }
  end

  defp invite_params(_row), do: %{}

  defp limit_reply(socket, count) do
    case ProjectLimiter.request_new_user(socket.assigns.project.id, count) do
      :ok ->
        :ok

      {:error, _reason, limit} ->
        reply_error(socket, Map.get(limit, :text) || @limited)
    end
  end

  # The name as typed, made URL-safe as the old form showed it would be.
  defp collection_name(%{"rawName" => raw}) when is_binary(raw),
    do: Helpers.url_safe_name(raw)

  defp collection_name(_params), do: nil

  defp project_collection(socket, id) do
    project_id = socket.assigns.project.id

    case Collections.get_collection_by_id(id) do
      {:ok, %{project_id: ^project_id} = collection} -> {:ok, collection}
      _not_here -> reply_error(socket, "Collection not found")
    end
  end

  # A keychain or collection action's answer; the lists are read again.
  defp changed_reply({:ok, _record}, socket, message) do
    socket |> assign_page_data() |> put_flash(:info, message) |> reply_ok()
  end

  defp changed_reply({:error, :unauthorized}, socket, _message),
    do: reply_error(socket, "You are not authorized to perform this action.")

  defp changed_reply({:error, :exceeds_limit, limit}, socket, _),
    do: reply_error(socket, Map.get(limit, :text) || @limited)

  # The collection form's field is the name as typed.
  defp changed_reply({:error, %{data: %Collection{}} = changeset}, socket, _),
    do: reply_error(socket, Helpers.copy_error(changeset, :name, :raw_name))

  defp changed_reply({:error, %Ecto.Changeset{} = changeset}, socket, _),
    do: reply_error(socket, changeset)

  defp delete_sandbox(socket, sandbox, typed) do
    if typed == sandbox.name do
      case Sandboxes.delete_sandbox(sandbox, socket.assigns.current_user) do
        {:ok, deleted} ->
          socket
          |> put_flash(
            :info,
            "Sandbox #{deleted.name} and all its associated descendants deleted"
          )
          |> push_navigate(to: ~p"/projects/#{socket.assigns.root_project.id}/w")
          |> reply_ok()

        {:error, :unauthorized} ->
          reply_error(socket, "You don't have permission to delete this sandbox")

        {:error, _reason} ->
          reply_error(
            socket,
            "Could not delete sandbox. Please try again later."
          )
      end
    else
      reply_error(socket, "does not match the sandbox name")
    end
  end

  defp delete_project(socket, project, typed) do
    changeset =
      Projects.validate_for_deletion(project, %{
        "name" => project.name,
        "name_confirmation" => typed
      })

    # The modal shows the message only, as on the admin projects page.
    with true <-
           changeset.valid? ||
             reply_error(socket, "doesn't match the project name"),
         {:ok, result} <-
           if(project.scheduled_deletion,
             do: Projects.delete_project_async(project),
             else: Projects.schedule_project_deletion(project)
           ) do
      message =
        case result do
          %Oban.Job{} ->
            "Project deletion started. This may take a while to complete."

          %Project{} ->
            "Project scheduled for deletion"
        end

      socket
      |> put_flash(:info, message)
      |> push_navigate(to: ~p"/projects")
      |> reply_ok()
    else
      {:error, %Ecto.Changeset{} = changeset} -> reply_error(socket, changeset)
      reply -> reply
    end
  end

  defp remove_user_tooltip(
         project_user,
         current_user,
         can_remove_project_user,
         project,
         sandbox?
       ) do
    cond do
      !can_remove_project_user ->
        "You do not have permission to remove a user"

      project_user.user_id == current_user.id ->
        "You cannot remove yourself"

      project_user.role == :owner ->
        "You cannot remove an owner"

      sandbox? and parent_admin?(project, project_user) ->
        "Cannot remove a user who is admin or owner on the parent project"

      true ->
        ""
    end
  end

  defp user_removable?(
         project_user,
         current_user,
         can_remove_project_user,
         project,
         sandbox?
       ) do
    can_remove_project_user and project_user.role != :owner and
      project_user.user_id != current_user.id and
      not (sandbox? and parent_admin?(project, project_user))
  end

  # Notification prefs are self-only (:edit_failure_alerts / :edit_digest_alerts),
  # so scoping the target to the project is not enough; the actor must own it.
  defp editable_alert_target?(_action, nil, _socket), do: false

  defp editable_alert_target?(action, project_user, socket) do
    Permissions.can?(
      :project_users,
      action,
      socket.assigns.current_user,
      project_user
    )
  end

  defp parent_admin?(project, %{user: %User{} = user}),
    do: Sandboxes.parent_admin?(project, user)

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

  # The page's lists, read once here so drawing the page again (a flash, a
  # sign-in) asks nothing more. Called again after an action changes one.
  defp assign_page_data(socket) do
    %{project: project, current_user: current_user} = socket.assigns
    project_users = Projects.get_project_users!(project.id)

    auth_methods =
      project
      |> WebhookAuthMethods.list_for_project()
      |> Lightning.Repo.preload([:channels, triggers: :workflow])

    assign(socket,
      project_users: project_users,
      webhook_auth_methods: auth_methods,
      collaborator_rows: Enum.map(project_users, &collaborator_row(&1, socket)),
      auth_method_rows:
        Enum.map(
          auth_methods,
          &auth_method_row(&1, socket.assigns.can_write_webhook_auth_method)
        ),
      collection_rows:
        project
        |> Collections.list_project_collections(order_by: [asc: :name])
        |> Enum.map(&collection_row/1),
      keychain_rows:
        project
        |> Credentials.list_keychain_credentials_for_project()
        |> Enum.map(&keychain_row/1),
      export_rows: Enum.map(socket.assigns.project_files, &export_row/1),
      collaborator_limit_error: get_collaborator_limit_error(project),
      github_user_connected: user_has_valid_oauth_token(current_user),
      sandbox_deletion: sandbox_deletion(project, socket.assigns.root_project)
    )
  end

  defp sandbox_deletion(_project, nil), do: nil

  defp sandbox_deletion(project, root_project) do
    %{
      rootName: root_project.name,
      descendantCount:
        project.id
        |> Projects.list_descendants()
        |> Enum.count(&is_nil(&1.scheduled_deletion))
    }
  end

  defp props(assigns) do
    %{project: project, parent_project: parent} = assigns

    %{
      project: %{
        id: project.id,
        parentId: project.parent_id,
        color: project.color
      },
      projectLabel: assigns.project_label,
      parent:
        parent &&
          %{name: parent.name, settingsHref: ~p"/projects/#{parent.id}/settings"},
      deleting: assigns.deleting,
      setup: setup_props(assigns),
      credentials:
        assigns
        |> CredentialIndex.props()
        |> Map.merge(%{
          keychainCredentials: assigns.keychain_rows,
          canCreateProjectCredential: assigns.can_create_project_credential,
          canCreateKeychainCredential: assigns.can_create_keychain_credential,
          # The policy asks the same question for creating and editing.
          canEditKeychainCredential: assigns.can_create_keychain_credential
        }),
      collections: %{
        collections: assigns.collection_rows,
        canManage: assigns.can_create_collection
      },
      webhookSecurity: %{
        authMethods: assigns.auth_method_rows,
        canWrite: assigns.can_write_webhook_auth_method
      },
      collaboration: %{
        collaborators: assigns.collaborator_rows,
        supportAccess: project.allow_support_access,
        canEditProject: assigns.can_edit_project,
        canAddProjectUser: assigns.can_add_project_user,
        addBlockedReason:
          if(assigns.can_add_project_user,
            do: assigns.collaborator_limit_error,
            else: "You are not authorized to perform this action"
          ),
        canReceiveFailureAlerts: assigns.can_receive_failure_alerts
      },
      security: %{
        requiresMfa: project.requires_mfa,
        canEditProject: assigns.can_edit_project,
        canRequireMfa: assigns.can_require_mfa
      },
      githubSync: github_props(assigns),
      dataStorage: %{
        historyRetentionPeriod: project.history_retention_period,
        dataclipRetentionPeriod: project.dataclip_retention_period,
        retentionPolicy: project.retention_policy,
        periods: assigns.data_retention_periods,
        # A component is drawn beside the page instead, as before.
        limitMessage:
          case assigns.data_retention_limit_message do
            %{function: func} when is_function(func) -> nil
            %{text: text} when is_binary(text) -> text
            _other -> nil
          end,
        canEdit: assigns.can_edit_data_retention
      },
      historyExports: assigns.export_rows
    }
  end

  defp setup_props(assigns) do
    %{project: project} = assigns

    %{
      name: project.name,
      description: project.description || "",
      env: project.env || "",
      concurrency: project.concurrency,
      exportHref: ~p"/download/yaml?id=#{project.id}",
      deleteHref: ~p"/projects/#{project.id}/settings/delete",
      gracePeriodDays: Lightning.Config.purge_deleted_after_days(),
      scheduledDeletion: project.scheduled_deletion,
      sandboxDeletion: assigns.sandbox_deletion,
      canEditProject: assigns.can_edit_project,
      canDeleteProject: assigns.can_delete_project
    }
  end

  # Connecting a repository needs the old form, drawn beside the page.
  defp connect_github_form?(assigns) do
    assigns.github_enabled and is_nil(assigns.project_repo_connection) and
      assigns.can_install_github and assigns.github_user_connected
  end

  defp github_props(assigns) do
    connection = assigns.project_repo_connection

    %{
      enabled: assigns.github_enabled,
      connection:
        connection &&
          %{
            repo: connection.repo,
            branch: connection.branch,
            githubInstallationId: connection.github_installation_id,
            configPath: ProjectRepoConnection.config_path(connection),
            syncVersion: connection.sync_version
          },
      userConnected: assigns.github_user_connected,
      # The OAuth link needs the app's settings, which exist only when enabled.
      connectAccountHref:
        if(assigns.github_enabled,
          do: GithubComponents.authorize_url(),
          else: ""
        ),
      canInstall: assigns.can_install_github,
      # An instance's GitHub sync limit disables the sync, as before.
      canInitiateSync:
        assigns.can_initiate_github_sync and is_nil(assigns[:github_banner])
    }
  end

  defp collaborator_row(project_user, socket) do
    %{current_user: current_user, project: project, sandbox?: sandbox?} =
      socket.assigns

    can_remove = socket.assigns.can_remove_project_user
    %{user: user} = project_user

    %{
      id: project_user.id,
      firstName: user.first_name,
      lastName: user.last_name || "",
      email: user.email,
      role: project_user.role,
      failureAlert: project_user.failure_alert,
      digest: project_user.digest,
      isCurrentUser: project_user.user_id == current_user.id,
      removeBlockedReason:
        if user_removable?(
             project_user,
             current_user,
             can_remove,
             project,
             sandbox?
           ) do
          nil
        else
          remove_user_tooltip(
            project_user,
            current_user,
            can_remove,
            project,
            sandbox?
          )
        end,
      ownedCredentialNames:
        user
        |> Credentials.list_user_credentials_in_project(project_user.project)
        |> Enum.map(& &1.name)
    }
  end

  # Only those who may edit a method see its username and masked secret.
  defp auth_method_row(auth_method, can_write?) do
    %{
      id: auth_method.id,
      name: auth_method.name,
      authType: auth_method.auth_type,
      username: if(can_write?, do: auth_method.username),
      maskedSecret: if(can_write?, do: masked_secret(auth_method), else: ""),
      triggers:
        Enum.map(auth_method.triggers, fn trigger ->
          %{
            id: trigger.id,
            name: trigger.workflow.name,
            href:
              ~p"/projects/#{trigger.workflow.project_id}/w/#{trigger.workflow.id}?s=#{trigger.id}"
          }
        end),
      channels:
        auth_method.channels
        |> Enum.sort_by(& &1.name)
        |> Enum.map(fn channel ->
          %{
            id: channel.id,
            name: channel.name,
            href: ~p"/projects/#{channel.project_id}/channels/#{channel.id}/edit"
          }
        end)
    }
  end

  # As the old form masked them: every character of a password, and all but
  # the last five of an API key (at most 15 stars before them).
  defp masked_secret(%{auth_type: :basic, password: password}),
    do: String.duplicate("*", String.length(password || ""))

  defp masked_secret(%{api_key: api_key}) do
    {last_5, first_n} =
      (api_key || "") |> String.graphemes() |> Enum.reverse() |> Enum.split(5)

    (last_5 ++ Enum.map(Enum.take(first_n, 15), fn _char -> "*" end))
    |> Enum.reverse()
    |> Enum.join()
  end

  defp collection_row(collection) do
    %{
      id: collection.id,
      name: collection.name,
      byteSizeSum: collection.byte_size_sum,
      downloadHref:
        ~p"/download/collections/#{collection.project_id}/#{collection.name}"
    }
  end

  defp keychain_row(keychain) do
    %{
      id: keychain.id,
      name: keychain.name,
      path: keychain.path,
      defaultCredential:
        keychain.default_credential &&
          %{
            id: keychain.default_credential.id,
            name: keychain.default_credential.name
          },
      ownerEmail: keychain.created_by.email
    }
  end

  defp export_row(file) do
    %{
      id: file.id,
      insertedAt: file.inserted_at,
      fileName: file.path && Path.basename(file.path),
      requestedBy: "#{file.created_by.first_name} #{file.created_by.last_name}",
      status: file.status,
      downloadHref:
        if(file.status == :completed, do: ~p"/project_files/#{file.id}/download")
    }
  end
end
