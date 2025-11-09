defmodule LightningWeb.WorkflowLive.Collaborate do
  @moduledoc """
  LiveView for collaborative workflow editing using shared Y.js documents.
  """
  use LightningWeb, {:live_view, container: {:div, []}}

  alias Lightning.Policies.Permissions
  alias Lightning.Workflows
  alias LightningWeb.Channels.WorkflowJSON

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
    {:noreply,
     assign(socket, show_credential_modal: true, credential_schema: schema)}
  end

  def handle_event("close_credential_modal_complete", _params, socket) do
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
      from_collab_editor={true}
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

  def handle_info(:clear_credential_page, socket) do
    {:noreply,
     assign(socket,
       credential_page: nil,
       credential_schema:
         Map.get(socket.assigns, :original_credential_schema, nil)
     )}
  end

  def handle_info({:update_credential_schema, schema}, socket) do
    {:noreply,
     assign(socket,
       credential_schema: schema,
       credential_page: nil
     )}
  end

  def handle_info({:update_selected_credential_type, type}, socket) do
    {:noreply,
     assign(socket,
       selected_credential_type_for_picker: type
     )}
  end

  def handle_info({:back_to_advanced_picker}, socket) do
    {:noreply,
     assign(socket,
       credential_page: :advanced_picker,
       show_credential_modal: true
     )}
  end

  @impl true
  def handle_info({:credential_saved, credential}, socket) do
    project = socket.assigns.project

    credential_data =
      case credential do
        %Lightning.Credentials.KeychainCredential{} ->
          %{
            id: credential.id,
            name: credential.name,
            schema: "keychain"
          }

        %Lightning.Credentials.Credential{} = cred ->
          if cred.project_credentials && length(cred.project_credentials) > 0 do
            project_credential_id = hd(cred.project_credentials).id

            %{
              project_credential_id: project_credential_id,
              id: cred.id,
              name: cred.name,
              schema: cred.schema
            }
          else
            %{
              id: cred.id,
              name: cred.name,
              schema: cred.schema
            }
          end
      end

    is_project_credential = Map.has_key?(credential_data, :project_credential_id)

    socket =
      push_event(socket, "credential_saved", %{
        credential: credential_data,
        is_project_credential: is_project_credential
      })

    broadcast_credential_update(socket, project)

    send(self(), :close_credential_modal_after_save)

    {:noreply, socket}
  end

  def handle_info(:close_credential_modal_after_save, socket) do
    {:noreply,
     assign(socket, show_credential_modal: false, credential_schema: nil)}
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
end
