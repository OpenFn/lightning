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
  alias Lightning.Policies.Permissions
  alias Lightning.Projects.ProjectCredential

  require Logger

  @impl true
  def join(
        "workflow:collaborate:" <> workflow_id = topic,
        %{"project_id" => project_id, "action" => action},
        socket
      ) do
    # Check if user is authenticated
    case socket.assigns[:current_user] do
      nil ->
        {:error, %{reason: "unauthorized"}}

      user ->
        # Fetch project first
        case Lightning.Projects.get_project(project_id) do
          nil ->
            {:error, %{reason: "project not found"}}

          project ->
            # Load or build workflow based on action
            case load_workflow(action, workflow_id, project, user) do
              {:ok, workflow} ->
                # Start collaboration with workflow struct
                {:ok, session_pid} =
                  Collaborate.start(user: user, workflow: workflow)

                project_user =
                  Lightning.Projects.get_project_user(
                    project,
                    user
                  )

                {:ok,
                 assign(socket,
                   workflow_id: workflow_id,
                   collaboration_topic: topic,
                   workflow: workflow,
                   project: project,
                   session_pid: session_pid,
                   project_user: project_user
                 )}

              {:error, reason} ->
                {:error, %{reason: reason}}
            end
        end
    end
  end

  # Handle missing params
  def join("workflow:collaborate:" <> _workflow_id, _params, _socket) do
    {:error, %{reason: "invalid parameters. project_id and action are required"}}
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
    project = socket.assigns.project

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
    project = socket.assigns.project
    project_user = socket.assigns.project_user

    async_task(socket, "get_context", fn ->
      %{
        user: render_user_context(user),
        project: render_project_context(project),
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

    with :ok <- authorize_edit_workflow(socket),
         {:ok, workflow} <- Session.save_workflow(session_pid, user) do
      {:reply,
       {:ok,
        %{
          saved_at: workflow.updated_at,
          lock_version: workflow.lock_version
        }}, socket}
    else
      error -> workflow_error_reply(socket, error)
    end
  end

  @impl true
  def handle_in("reset_workflow", _params, socket) do
    session_pid = socket.assigns.session_pid
    user = socket.assigns.current_user

    with :ok <- authorize_edit_workflow(socket),
         {:ok, workflow} <- Session.reset_workflow(session_pid, user) do
      {:reply,
       {:ok,
        %{
          lock_version: workflow.lock_version,
          workflow_id: workflow.id
        }}, socket}
    else
      error -> workflow_error_reply(socket, error)
    end
  end

  @impl true
  def handle_in("validate_workflow_name", %{"workflow" => params}, socket) do
    project = socket.assigns.project

    # Apply name uniqueness logic
    validated_params = ensure_unique_name(params, project)

    {:reply, {:ok, %{workflow: validated_params}}, socket}
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
      Permissions.can?(
        :project_users,
        :edit_workflow,
        user,
        project_user
      )

    %{
      can_edit_workflow: can_edit
    }
  end

  # Private helper functions for save_workflow and reset_workflow

  defp workflow_error_reply(socket, {:error, %{type: type, message: message}}) do
    {:reply,
     {:error,
      %{
        errors: %{base: [message]},
        type: type
      }}, socket}
  end

  defp workflow_error_reply(socket, {:error, :workflow_deleted}) do
    {:reply,
     {:error,
      %{
        errors: %{base: ["This workflow has been deleted"]},
        type: "workflow_deleted"
      }}, socket}
  end

  defp workflow_error_reply(socket, {:error, :deserialization_failed}) do
    {:reply,
     {:error,
      %{
        errors: %{base: ["Failed to extract workflow data from editor"]},
        type: "deserialization_error"
      }}, socket}
  end

  defp workflow_error_reply(socket, {:error, :internal_error}) do
    {:reply,
     {:error,
      %{
        errors: %{base: ["An internal error occurred"]},
        type: "internal_error"
      }}, socket}
  end

  defp workflow_error_reply(socket, {:error, %Ecto.Changeset{} = changeset}) do
    {:reply,
     {:error,
      %{
        errors: format_changeset_errors(changeset),
        type: determine_error_type(changeset)
      }}, socket}
  end

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

  # Authorizes edit operations on the workflow by checking current user permissions.
  #
  # This function refetches the project_user to get the latest role, ensuring
  # that permission changes made during an active session are enforced.
  #
  # Returns :ok if authorized, {:error, %{type: string, message: string}} if not.
  defp authorize_edit_workflow(socket) do
    user = socket.assigns.current_user
    project = socket.assigns.project

    project_user = Lightning.Projects.get_project_user(project, user)

    case Permissions.can(
           :project_users,
           :edit_workflow,
           user,
           project_user
         ) do
      :ok ->
        :ok

      {:error, :unauthorized} ->
        {:error,
         %{
           type: "unauthorized",
           message: "You don't have permission to edit this workflow"
         }}
    end
  end

  # Private helper functions for validate_workflow_name

  defp ensure_unique_name(params, project) do
    workflow_name =
      params["name"]
      |> to_string()
      |> String.trim()
      |> case do
        "" -> "Untitled workflow"
        name -> name
      end

    existing_workflows = Lightning.Projects.list_workflows(project)
    unique_name = generate_unique_name(workflow_name, existing_workflows)

    Map.put(params, "name", unique_name)
  end

  defp generate_unique_name(base_name, existing_workflows) do
    existing_names = MapSet.new(existing_workflows, & &1.name)

    if MapSet.member?(existing_names, base_name) do
      find_available_name(base_name, existing_names)
    else
      base_name
    end
  end

  defp find_available_name(base_name, existing_names) do
    1
    |> Stream.iterate(&(&1 + 1))
    |> Stream.map(&"#{base_name} #{&1}")
    |> Enum.find(&name_available?(&1, existing_names))
  end

  defp name_available?(name, existing_names) do
    not MapSet.member?(existing_names, name)
  end

  # Load workflow for "edit" action - fetch from database
  defp load_workflow("edit", workflow_id, project, user) do
    case Lightning.Workflows.get_workflow(workflow_id) do
      nil ->
        {:error, "workflow not found"}

      workflow ->
        # Verify project matches
        if workflow.project_id != project.id do
          {:error, "workflow does not belong to specified project"}
        else
          # Verify permissions
          case Permissions.can(
                 :workflows,
                 :access_read,
                 user,
                 project
               ) do
            :ok ->
              {:ok, workflow}

            {:error, :unauthorized} ->
              {:error, "unauthorized"}
          end
        end
    end
  end

  # Load workflow for "new" action - build workflow struct
  defp load_workflow("new", workflow_id, project, user) do
    # Verify permissions on project
    case Permissions.can(
           :project_users,
           :create_workflow,
           user,
           project
         ) do
      :ok ->
        # Build minimal workflow struct for new workflow
        workflow = %Lightning.Workflows.Workflow{
          id: workflow_id,
          project_id: project.id,
          name: "Untitled workflow",
          jobs: [],
          edges: [],
          triggers: []
        }

        {:ok, workflow}

      {:error, :unauthorized} ->
        {:error, "unauthorized"}
    end
  end

  # Handle invalid action
  defp load_workflow(action, _workflow_id, _project, _user) do
    {:error, "invalid action '#{action}', must be 'new' or 'edit'"}
  end
end
