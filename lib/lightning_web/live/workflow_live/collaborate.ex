defmodule LightningWeb.WorkflowLive.Collaborate do
  @moduledoc """
  LiveView for collaborative workflow editing using shared Y.js documents.
  """
  use LightningWeb, {:live_view, container: {:div, []}}

  alias Lightning.Policies.Permissions
  alias Lightning.Workflows

  on_mount {LightningWeb.Hooks, :project_scope}

  @impl true
  def mount(%{"id" => workflow_id}, _session, socket) do
    workflow = Workflows.get_workflow!(workflow_id)
    project = socket.assigns.project

    {:ok,
     socket
     |> assign(
       active_menu_item: :overview,
       page_title: "Collaborate on #{workflow.name}",
       workflow: workflow,
       workflow_id: workflow_id,
       project: project,
       show_credential_modal: false,
       credential_schema: nil
     )}
  end

  @impl true
  def handle_params(_params, _url, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("open_credential_modal", %{"schema" => schema}, socket) do
    # Reset modal state when opening - this will remount the component if it was hidden
    {:noreply,
     assign(socket, show_credential_modal: true, credential_schema: schema)}
  end

  def handle_event("close_credential_modal_complete", _params, socket) do
    # Called after modal is fully closed and animations are complete
    # Reset server state so the modal can be opened again
    {:noreply,
     assign(socket, show_credential_modal: false, credential_schema: nil)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div
      id="collaborative-editor-react"
      class="h-full"
      phx-hook="ReactComponent"
      phx-update="ignore"
      data-react-name="CollaborativeEditor"
      data-react-file={~p"/assets/js/collaborative-editor/CollaborativeEditor.js"}
      data-workflow-id={@workflow_id}
      data-workflow-name={@workflow.name}
      data-project-id={@workflow.project_id}
      data-project-name={@project.name}
      data-project-color={@project.color}
      data-root-project-id={
        if @project.parent, do: Lightning.Projects.root_of(@project).id, else: nil
      }
      data-root-project-name={
        if @project.parent, do: Lightning.Projects.root_of(@project).name, else: nil
      }
      data-project-env={@project.env}
    />

    <.live_component
      :if={@show_credential_modal}
      module={LightningWeb.CredentialLive.CredentialFormComponent}
      id="new-credential-modal"
      action={:new}
      current_user={@current_user}
      project={@project}
      projects={[@project]}
      credential={
        %Lightning.Credentials.Credential{
          schema: @credential_schema,
          user_id: @current_user.id,
          project_credentials: [
            %Lightning.Projects.ProjectCredential{
              project_id: @project.id
            }
          ]
        }
      }
      on_save={
        fn credential ->
          send(self(), {:credential_saved, credential})
          :ok
        end
      }
      on_modal_close={
        JS.dispatch("close_credential_modal", to: "#collaborative-editor-react")
      }
      return_to={nil}
      sandbox_id={@project.parent_id}
      can_create_project_credential={
        Permissions.can?(
          :project_users,
          :create_project_credential,
          @current_user,
          @project
        )
      }
    />
    """
  end

  @impl true
  def handle_info({:credential_saved, credential}, socket) do
    project = socket.assigns.project

    # Format credential data for React
    # Determine if it's a project or keychain credential
    {credential_id, is_project_credential} =
      if credential.project_credentials &&
           length(credential.project_credentials) > 0 do
        # Project credential
        {hd(credential.project_credentials).id, true}
      else
        # Keychain credential
        {credential.id, false}
      end

    # Build credential payload matching the format React expects
    credential_data =
      if is_project_credential do
        %{
          project_credential_id: credential_id,
          id: credential.id,
          name: credential.name,
          schema: credential.schema
        }
      else
        %{
          id: credential_id,
          name: credential.name,
          schema: credential.schema
        }
      end

    # Push event to React with the full credential data
    socket =
      push_event(socket, "credential_saved", %{
        credential: credential_data,
        is_project_credential: is_project_credential
      })

    # Broadcast credential update to all connected clients on this workflow channel
    # This ensures the CredentialStore receives the update in real-time
    broadcast_credential_update(socket, project)

    # Update server state to close the modal
    send(self(), :close_credential_modal_after_save)

    {:noreply, socket}
  end

  def handle_info(:close_credential_modal_after_save, socket) do
    {:noreply,
     assign(socket, show_credential_modal: false, credential_schema: nil)}
  end

  defp broadcast_credential_update(socket, project) do
    # Fetch updated credentials list
    credentials =
      Lightning.Projects.list_project_credentials(project)
      |> Enum.concat(
        Lightning.Credentials.list_keychain_credentials_for_project(project)
      )
      |> render_credentials()

    # Broadcast to all connected clients on the workflow channel
    # The CredentialStore listens for this "credentials_updated" event
    Phoenix.PubSub.broadcast(
      Lightning.PubSub,
      "workflow:collaborate:#{socket.assigns.workflow_id}",
      %{event: "credentials_updated", payload: credentials}
    )
  end

  defp render_credentials(credentials) do
    alias Lightning.Credentials.KeychainCredential
    alias Lightning.Projects.ProjectCredential

    {project_credentials, keychain_credentials} =
      credentials
      |> Enum.split_with(fn
        %ProjectCredential{} -> true
        %KeychainCredential{} -> false
      end)

    %{
      project_credentials:
        project_credentials
        |> Enum.map(fn %ProjectCredential{
                         credential: credential,
                         id: project_credential_id
                       } ->
          %{
            id: credential.id,
            project_credential_id: project_credential_id,
            name: credential.name,
            external_id: credential.external_id,
            schema: credential.schema,
            owner: render_owner(credential.user),
            oauth_client_name: render_oauth_client_name(credential.oauth_client),
            inserted_at: credential.inserted_at,
            updated_at: credential.updated_at
          }
        end),
      keychain_credentials:
        keychain_credentials
        |> Enum.map(fn %KeychainCredential{} = keychain_credential ->
          %{
            id: keychain_credential.id,
            name: keychain_credential.name,
            path: keychain_credential.path,
            default_credential_id: keychain_credential.default_credential_id,
            inserted_at: keychain_credential.inserted_at,
            updated_at: keychain_credential.updated_at
          }
        end)
    }
  end

  defp render_owner(nil), do: nil

  defp render_owner(user) do
    %{
      id: user.id,
      name: "#{user.first_name} #{user.last_name}",
      email: user.email
    }
  end

  defp render_oauth_client_name(nil), do: nil
  defp render_oauth_client_name(%{name: name}), do: name
end
