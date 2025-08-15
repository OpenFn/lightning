defmodule LightningWeb.WorkflowChannel do
  @moduledoc """
  Phoenix Channel for handling binary Yjs collaboration messages.

  Unlike LiveView events, Phoenix Channels properly support binary data
  transmission without JSON serialization.
  """
  use LightningWeb, :channel

  alias Lightning.Collaboration.Session
  alias Lightning.Collaboration.Utils
  alias Lightning.Credentials.KeychainCredential
  alias Lightning.Projects.ProjectCredential

  require Logger

  @impl true
  def join("workflow:collaborate:" <> workflow_id = topic, _params, socket) do
    # Check if user is authenticated
    case socket.assigns[:current_user] do
      nil ->
        {:error, %{reason: "unauthorized"}}

      user ->
        # Get workflow and verify user has access to its project
        case Lightning.Workflows.get_workflow(workflow_id, include: [:project]) do
          nil ->
            {:error, %{reason: "workflow not found"}}

          workflow ->
            case Lightning.Policies.Permissions.can(
                   :workflows,
                   :access_read,
                   user,
                   workflow.project
                 ) do
              :ok ->
                {:ok, session_pid} =
                  Session.start(workflow_id)

                {:ok,
                 assign(socket,
                   workflow_id: workflow_id,
                   collaboration_topic: topic,
                   workflow: workflow,
                   session_pid: session_pid
                 )}

              {:error, :unauthorized} ->
                {:error, %{reason: "unauthorized"}}
            end
        end
    end
  end

  @impl true
  def handle_in("request_adaptors", _payload, socket) do
    adaptors = Lightning.AdaptorRegistry.all()
    {:reply, {:ok, %{adaptors: adaptors}}, socket}
  end

  @impl true
  def handle_in("request_credentials", _payload, socket) do
    credentials =
      Lightning.Projects.list_project_credentials(
        socket.assigns.workflow.project
      )
      |> Enum.concat(
        Lightning.Credentials.list_keychain_credentials_for_project(
          socket.assigns.workflow.project
        )
      )
      |> render_credentials()

    {:reply, {:ok, %{credentials: credentials}}, socket}
  end

  @impl true
  def handle_in("yjs_sync", {:binary, chunk}, socket) do
    Session.start_sync(socket.assigns.session_pid, chunk)
    {:noreply, socket}
  end

  def handle_in("yjs", {:binary, chunk}, socket) do
    Logger.debug("""
    WorkflowChannel: handle_in, yjs
      from=#{inspect(self())}
      chunk=#{inspect(Utils.decipher_message(chunk))}
    """)

    Session.send_yjs_message(socket.assigns.session_pid, chunk)
    {:noreply, socket}
  end

  @impl true
  def handle_info({:yjs, chunk}, socket) do
    push(socket, "yjs", {:binary, chunk})
    {:noreply, socket}
  end

  @impl true
  def handle_info(
        {:DOWN, _ref, :process, _pid, _reason},
        socket
      ) do
    {:stop, {:error, "remote process crash"}, socket}
  end

  defp render_credentials(credentials) do
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
            production: credential.production,
            schema: credential.schema,
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
end
