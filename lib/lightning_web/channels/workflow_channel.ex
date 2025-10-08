defmodule LightningWeb.WorkflowChannel do
  @moduledoc """
  Phoenix Channel for handling binary Yjs collaboration messages.

  Unlike LiveView events, Phoenix Channels properly support binary data
  transmission without JSON serialization.
  """
  use LightningWeb, :channel

  alias Lightning.Collaborate
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
                  Collaborate.start(user: user, workflow_id: workflow_id)

                project_user =
                  Lightning.Projects.get_project_user(
                    workflow.project,
                    user
                  )

                {:ok,
                 assign(socket,
                   workflow_id: workflow_id,
                   collaboration_topic: topic,
                   workflow: workflow,
                   session_pid: session_pid,
                   project_user: project_user
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
  def handle_in("get_context", _payload, socket) do
    user = socket.assigns[:current_user]
    workflow = socket.assigns.workflow
    project_user = socket.assigns.project_user

    async_task(socket, "get_context", fn ->
      %{
        user: render_user_context(user),
        project: render_project_context(workflow.project),
        config: render_config_context(),
        permissions: render_permissions(user, project_user),
        latest_snapshot_lock_version: workflow.lock_version
      }
    end)
  end

  @impl true
  def handle_in("yjs_sync", {:binary, chunk}, socket) do
    Logger.debug("""
    WorkflowChannel: handle_in, yjs_sync
      from=#{inspect(self())}
      chunk=#{inspect(Utils.decipher_message(chunk))}
    """)

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

  @doc """
  Handles explicit workflow save requests from the collaborative editor.

  The save operation:
  1. Asks Session to extract and save the current Y.Doc state
  2. Session handles all Y.Doc interaction internally
  3. Returns success/error to the client

  Note: By the time this message is processed, all prior Y.js sync messages
  have been processed due to Phoenix Channel's synchronous per-socket handling.

  Success response: {:ok, %{saved_at: DateTime, lock_version: integer}}
  Error response: {:error, %{errors: map, type: string}}
  """
  @impl true
  def handle_in("save_workflow", _params, socket) do
    session_pid = socket.assigns.session_pid
    user = socket.assigns.current_user

    case Session.save_workflow(session_pid, user) do
      {:ok, workflow} ->
        {:reply,
         {:ok,
          %{
            saved_at: DateTime.utc_now(),
            lock_version: workflow.lock_version
          }}, socket}

      {:error, :workflow_deleted} ->
        {:reply,
         {:error,
          %{
            errors: %{base: ["This workflow has been deleted"]},
            type: "workflow_deleted"
          }}, socket}

      {:error, :deserialization_failed} ->
        {:reply,
         {:error,
          %{
            errors: %{base: ["Failed to extract workflow data from editor"]},
            type: "deserialization_error"
          }}, socket}

      {:error, :internal_error} ->
        {:reply,
         {:error,
          %{
            errors: %{base: ["An internal error occurred"]},
            type: "internal_error"
          }}, socket}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:reply,
         {:error,
          %{
            errors: format_changeset_errors(changeset),
            type: determine_error_type(changeset)
          }}, socket}
    end
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

      "get_context" ->
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

  defp render_user_context(nil), do: nil

  defp render_user_context(user) do
    %{
      id: user.id,
      email: user.email,
      first_name: user.first_name,
      last_name: user.last_name,
      email_confirmed: !is_nil(user.confirmed_at),
      inserted_at: user.inserted_at
    }
  end

  defp render_project_context(nil), do: nil

  defp render_project_context(project) do
    %{
      id: project.id,
      name: project.name
    }
  end

  defp render_config_context do
    %{
      require_email_verification:
        Lightning.Config.check_flag?(:require_email_verification)
    }
  end

  defp render_permissions(user, project_user) do
    can_edit =
      Lightning.Policies.Permissions.can?(
        :project_users,
        :edit_workflow,
        user,
        project_user
      )

    %{
      can_edit_workflow: can_edit
    }
  end

  # Private helper functions for save_workflow

  defp format_changeset_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
  end

  defp determine_error_type(changeset) do
    if changeset.errors[:lock_version] do
      "optimistic_lock_error"
    else
      "validation_error"
    end
  end
end
