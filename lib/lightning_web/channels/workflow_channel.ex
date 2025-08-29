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
                  Session.start(user: user, workflow_id: workflow_id)

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
    async_task(socket, "request_adaptors", fn ->
      adaptors = Lightning.AdaptorRegistry.all()
      %{adaptors: adaptors}
    end)
  end

  @impl true
  def handle_in("request_credentials", _payload, socket) do
    project = socket.assigns.workflow.project

    async_task(socket, "request_credentials", fn ->
      credentials =
        Lightning.Projects.list_project_credentials(project)
        |> Enum.concat(
          Lightning.Credentials.list_keychain_credentials_for_project(project)
        )
        |> render_credentials()

      %{credentials: credentials}
    end)
  end

  @impl true
  def handle_in("request_current_user", _payload, socket) do
    user = socket.assigns[:current_user]

    async_task(socket, "request_current_user", fn ->
      current_user = render_current_user(user)
      %{current_user: current_user}
    end)
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
  def handle_info({:async_reply, socket_ref, event, reply}, socket) do
    case event do
      "request_adaptors" ->
        reply(socket_ref, reply)
        {:noreply, socket}

      "request_credentials" ->
        reply(socket_ref, reply)
        {:noreply, socket}

      "request_current_user" ->
        reply(socket_ref, reply)
        {:noreply, socket}

      _ ->
        Logger.warning("Unhandled async reply for event: #{event}")
        {:noreply, socket}
    end
  end

  @impl true
  def handle_info(%{event: "presence_diff", payload: _diff}, socket) do
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

  defp async_task(socket, event, task_fn) do
    channel_pid = self()
    socket_ref = socket_ref(socket)

    Task.start_link(fn ->
      try do
        result = task_fn.()

        send(
          channel_pid,
          {:async_reply, socket_ref, event, {:ok, result}}
        )
      rescue
        error ->
          Logger.error("Failed to handle #{event}: #{inspect(error)}")

          send(
            channel_pid,
            {:async_reply, socket_ref, event,
             {:error, %{reason: "failed to handle #{event}"}}}
          )
      end
    end)

    {:noreply, socket}
  end

  defp render_current_user(user) do
    %{
      id: user.id,
      email: user.email,
      first_name: user.first_name,
      last_name: user.last_name,
      inserted_at: user.inserted_at,
      updated_at: user.updated_at
    }
  end
end
