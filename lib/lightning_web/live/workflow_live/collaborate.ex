defmodule LightningWeb.WorkflowLive.Collaborate do
  @moduledoc """
  LiveView for collaborative workflow editing using shared Y.js documents.

  This LiveView handles both creating new workflows and editing existing ones:
  - For new workflows: Creates an ephemeral workflow with a temporary UUID
  - For existing workflows: Loads the workflow from the database

  Supports credential creation modal for both new and existing workflows.
  """
  use LightningWeb, {:live_view, container: {:div, []}}

  alias Lightning.Policies.Permissions
  alias Lightning.Workflows
  alias Lightning.Workflows.WebhookAuthMethod
  alias Lightning.Workflows.Workflow
  alias LightningWeb.Channels.WorkflowJSON

  on_mount({LightningWeb.Hooks, :project_scope})

  @impl true
  def mount(params, _session, %{assigns: %{project: project}} = socket) do
    {:ok,
     socket
     |> assign(workflow_assigns(params, project))
     |> assign(
       active_menu_item: :overview,
       project: project,
       show_credential_modal: false,
       credential_schema: nil,
       show_webhook_auth_modal: false,
       webhook_auth_method: nil
     )}
  end

  @impl true
  def handle_params(_params, _url, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("open_credential_modal", %{"schema" => schema}, socket) do
    {:noreply,
     assign(socket, show_credential_modal: true, credential_schema: schema)}
  end

  def handle_event("close_credential_modal", _params, socket) do
    {:noreply,
     assign(socket, show_credential_modal: false, credential_schema: nil)}
  end

  def handle_event("open_webhook_auth_modal", %{}, socket) do
    # Open the webhook auth method creation modal
    # Create a new webhook auth method for the form
    webhook_auth_method = %WebhookAuthMethod{
      project_id: socket.assigns.project.id
    }

    {:noreply,
     assign(socket,
       show_webhook_auth_modal: true,
       webhook_auth_method: webhook_auth_method
     )}
  end

  def handle_event("close_webhook_auth_modal_complete", _params, socket) do
    # Called after modal is fully closed and animations are complete
    # Reset server state so the modal can be opened again
    {:noreply,
     assign(socket,
       show_webhook_auth_modal: false,
       webhook_auth_method: nil
     )}
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
      data-is-new-workflow={if @is_new_workflow, do: "true", else: nil}
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

    <.modal
      :if={@show_webhook_auth_modal}
      id="webhook-auth-method-modal"
      show={true}
      on_close={
        JS.dispatch("close_webhook_auth_modal", to: "#collaborative-editor-react")
      }
      width="min-w-1/3 max-w-xl"
    >
      <.live_component
        module={LightningWeb.WorkflowLive.WebhookAuthMethodFormComponent}
        id="webhook-auth-method-form"
        action={:new}
        webhook_auth_method={@webhook_auth_method}
        current_user={@current_user}
        on_close={
          JS.dispatch("close_webhook_auth_modal", to: "#collaborative-editor-react")
        }
        on_save={
          fn _ ->
            send(self(), :webhook_auth_method_saved)
            :ok
          end
        }
        return_to={nil}
      />
    </.modal>
    """
  end

  @impl true
  def handle_info({:credential_saved, credential}, socket) do
    project = socket.assigns.project
    credential_payload = build_credential_payload(credential)

    {:noreply,
     socket
     |> push_event("credential_saved", credential_payload)
     |> then(fn socket ->
       broadcast_credential_update(socket, project)
       socket
     end)
     |> assign(show_credential_modal: false, credential_schema: nil)}
  end

  defp workflow_assigns(params, project) do
    case params do
      %{"id" => workflow_id} ->
        workflow = Workflows.get_workflow!(workflow_id)

        %{
          workflow: workflow,
          workflow_id: workflow_id,
          is_new_workflow: false,
          page_title: "Collaborate on #{workflow.name}"
        }

      _other ->
        workflow_id = Ecto.UUID.generate()

        workflow = %Workflow{
          id: workflow_id,
          name: "Untitled Workflow",
          project_id: project.id
        }

        %{
          workflow: workflow,
          workflow_id: workflow_id,
          is_new_workflow: true,
          page_title: "New Workflow"
        }
    end
  end

  defp build_credential_payload(credential) do
    {credential_id, is_project_credential} =
      determine_credential_type(credential)

    credential_data =
      build_credential_data(credential_id, credential, is_project_credential)

    %{
      credential: credential_data,
      is_project_credential: is_project_credential
    }
  end

  defp determine_credential_type(credential) do
    case credential.project_credentials do
      [%{id: id} | _] -> {id, true}
      _ -> {credential.id, false}
    end
  end

  defp build_credential_data(credential_id, credential, is_project_credential) do
    base_data = %{
      id: credential.id,
      name: credential.name,
      schema: credential.schema
    }

    if is_project_credential do
      Map.put(base_data, :project_credential_id, credential_id)
    else
      %{base_data | id: credential_id}
    end
  end

  def handle_info(:webhook_auth_method_saved, socket) do
    # Broadcast webhook auth methods update to all connected clients
    broadcast_webhook_auth_methods_update(socket)

    socket
    |> assign(
      show_webhook_auth_modal: false,
      webhook_auth_method: nil
    )
    |> push_event("webhook_auth_method_saved", %{})
    |> noreply()
  end

  defp broadcast_credential_update(socket, project) do
    credentials =
      Lightning.Projects.list_project_credentials(project)
      |> Enum.concat(
        Lightning.Credentials.list_keychain_credentials_for_project(project)
      )
      |> WorkflowJSON.render()

    Phoenix.PubSub.broadcast(
      Lightning.PubSub,
      "workflow:collaborate:#{socket.assigns.workflow_id}",
      %{event: "credentials_updated", payload: credentials}
    )
  end

  defp broadcast_webhook_auth_methods_update(socket) do
    # Fetch updated webhook auth methods list
    project = socket.assigns.project

    webhook_auth_methods =
      Lightning.WebhookAuthMethods.list_for_project(project)
      |> Enum.map(fn auth_method ->
        %{
          id: auth_method.id,
          name: auth_method.name,
          auth_type: auth_method.auth_type,
          username: auth_method.username,
          project_id: auth_method.project_id,
          inserted_at: auth_method.inserted_at,
          updated_at: auth_method.updated_at
        }
      end)

    # Wrap in a map to match Phoenix WebSocket serializer requirements
    payload = %{webhook_auth_methods: webhook_auth_methods}

    # Broadcast to all connected clients on the workflow channel
    Phoenix.PubSub.broadcast(
      Lightning.PubSub,
      "workflow:collaborate:#{socket.assigns.workflow_id}",
      %{event: "webhook_auth_methods_updated", payload: payload}
    )
  end
end
