defmodule LightningWeb.AiAssistantChannel do
  @moduledoc """
  Phoenix Channel for AI Assistant communication in the collaborative editor.

  Supports two session types:
  - job_code: AI assistance for individual job implementation
  - workflow_template: AI-powered workflow generation

  ## Topics
  - "ai_assistant:job_code:{session_id}"
  - "ai_assistant:workflow_template:{session_id}"
  """
  use LightningWeb, :channel

  alias Lightning.AiAssistant
  alias Lightning.Jobs
  alias Lightning.Policies.Permissions
  alias Lightning.Projects
  alias Lightning.Workflows

  require Logger

  @impl true
  def join(
        "ai_assistant:" <> rest,
        params,
        socket
      ) do
    with {:user, user} when not is_nil(user) <-
           {:user, socket.assigns[:current_user]},
         {:ok, session_type, session_id} <- parse_topic(rest),
         {:session, {:ok, session}} <-
           {:session,
            load_or_create_session(session_type, session_id, params, user)},
         :ok <- authorize_session_access(session, user) do
      # Subscribe to session-specific PubSub topic for message updates
      Lightning.subscribe("ai_session:#{session.id}")

      Logger.info("""
      Joining AI Assistant channel:
        session_type: #{session_type}
        session_id: #{session.id}
        user_id: #{user.id}
      """)

      # Messages are already preloaded with the session
      {:ok,
       %{
         session_id: session.id,
         session_type: session_type,
         messages: format_messages(session.messages)
       },
       assign(socket,
         session_id: session.id,
         session_type: session_type,
         session: session
       )}
    else
      {:user, nil} ->
        {:error, %{reason: "unauthorized"}}

      {:session_type, nil} ->
        {:error, %{reason: "invalid topic format"}}

      {:session, {:error, reason}} ->
        {:error, %{reason: reason}}

      {:error, :unauthorized} ->
        {:error, %{reason: "unauthorized"}}
    end
  end

  @impl true
  def handle_in("new_message", %{"content" => content} = params, socket) do
    session = socket.assigns.session
    user = socket.assigns.current_user

    require Logger

    Logger.debug("""
    [AiAssistantChannel] Received new_message
    Session type: #{socket.assigns.session_type}
    Session ID: #{session.id}
    Has 'code' in params: #{Map.has_key?(params, "code")}
    Code length in params: #{if params["code"], do: byte_size(params["code"]), else: 0}
    """)

    # Validate message content
    if String.trim(content) == "" do
      {:reply, {:error, %{reason: "Message cannot be empty"}}, socket}
    else
      # Extract options based on session type
      opts = extract_message_options(socket.assigns.session_type, params)

      Logger.debug("""
      [AiAssistantChannel] Extracted options
      Opts: #{inspect(opts)}
      Code in opts: #{inspect(Keyword.get(opts, :code))}
      """)

      case AiAssistant.save_message(
             session,
             %{role: :user, content: content, user: user},
             opts
           ) do
        {:ok, updated_session} ->
          # Message saved successfully, processing will happen async via Oban
          # Get the last message from the updated session
          message = List.last(updated_session.messages)
          {:reply, {:ok, %{message: format_message(message)}}, socket}

        {:error, changeset} ->
          errors = format_changeset_errors(changeset)

          {:reply, {:error, %{reason: "validation_error", errors: errors}},
           socket}
      end
    end
  end

  @impl true
  def handle_in("retry_message", %{"message_id" => message_id}, socket) do
    # First get the message to verify it belongs to this session
    message = Lightning.Repo.get(ChatMessage, message_id)

    if message && message.chat_session_id == socket.assigns.session_id do
      case AiAssistant.retry_message(message) do
        {:ok, {updated_message, _oban_job}} ->
          {:reply, {:ok, %{message: format_message(updated_message)}}, socket}

        {:error, changeset} ->
          errors = format_changeset_errors(changeset)

          {:reply, {:error, %{reason: "validation_error", errors: errors}},
           socket}
      end
    else
      {:reply, {:error, %{reason: "message not found or unauthorized"}}, socket}
    end
  end

  @impl true
  def handle_in("mark_disclaimer_read", _params, socket) do
    user = socket.assigns.current_user

    case AiAssistant.mark_disclaimer_read(user) do
      {:ok, _user} ->
        {:reply, {:ok, %{success: true}}, socket}

      {:error, reason} ->
        {:reply, {:error, %{reason: reason}}, socket}
    end
  end

  @impl true
  def handle_in("list_sessions", params, socket) do
    session = socket.assigns.session
    session_type = socket.assigns.session_type

    require Logger

    Logger.debug("""
    [AiAssistantChannel] list_sessions request
    Session type: #{session_type}
    Session ID: #{session.id}
    Params: #{inspect(params)}
    """)

    offset = Map.get(params, "offset", 0)
    limit = Map.get(params, "limit", 20)

    with {:ok, resource} <- get_resource_for_session_type(session_type, session),
         %{sessions: sessions, pagination: pagination} <-
           AiAssistant.list_sessions(resource, :desc,
             offset: offset,
             limit: limit
           ) do
      Logger.debug("""
      [AiAssistantChannel] list_sessions result
      Resource: #{inspect(resource)}
      Session count: #{length(sessions)}
      Total count: #{pagination.total_count}
      """)

      formatted_sessions = Enum.map(sessions, &format_session/1)

      {:reply,
       {:ok,
        %{
          sessions: formatted_sessions,
          pagination: %{
            total_count: pagination.total_count,
            has_next_page: pagination.has_next_page,
            has_prev_page: pagination.has_prev_page
          }
        }}, socket}
    else
      {:error, reason} ->
        {:reply, {:error, %{reason: reason}}, socket}
    end
  end

  # Handle PubSub broadcasts for message status updates
  @impl true
  def handle_info(
        {:ai_assistant, :message_status_changed,
         %{status: {status, updated_session}, session_id: session_id}},
        socket
      ) do
    if socket.assigns.session_id == session_id do
      # When status changes to :success, the updated_session will have the new assistant message
      # Push the status update and, if it's success, also push the new message
      case status do
        :success ->
          # Find the latest assistant message (the AI response)
          assistant_message =
            updated_session.messages
            |> Enum.reverse()
            |> Enum.find(fn msg -> msg.role == :assistant end)

          if assistant_message do
            push(socket, "new_message", %{
              message: format_message(assistant_message)
            })
          end

        _ ->
          # For other status changes, just notify about the status
          # The frontend can use this to show loading states
          :ok
      end
    end

    {:noreply, socket}
  end

  # Fallback for status updates without session data (shouldn't happen with current MessageProcessor)
  @impl true
  def handle_info(
        {:ai_assistant, :message_status_changed,
         %{status: _status, session_id: _session_id}},
        socket
      ) do
    {:noreply, socket}
  end

  @impl true
  def handle_info(_msg, socket) do
    {:noreply, socket}
  end

  # Private helpers

  defp parse_topic(topic) do
    case String.split(topic, ":", parts: 2) do
      ["job_code", session_id] -> {:ok, "job_code", session_id}
      ["workflow_template", session_id] -> {:ok, "workflow_template", session_id}
      _ -> {:error, :invalid_topic}
    end
  end

  defp load_or_create_session("job_code", session_id, params, user) do
    case session_id do
      "new" ->
        # Create new job code session
        with {:job_id, job_id} when not is_nil(job_id) <-
               {:job_id, params["job_id"]},
             {:job, job} when not is_nil(job) <-
               {:job, Jobs.get_job!(job_id)},
             {:content, content} when not is_nil(content) <-
               {:content, params["content"]} do
          opts = extract_session_options("job_code", params)
          AiAssistant.create_session(job, user, content, opts)
        else
          {:job_id, nil} -> {:error, "job_id required"}
          {:job, nil} -> {:error, "job not found"}
          {:content, nil} -> {:error, "initial content required"}
        end

      _existing_id ->
        # Load existing session
        case AiAssistant.get_session!(session_id) do
          nil -> {:error, "session not found"}
          session -> {:ok, session}
        end
    end
  end

  defp load_or_create_session("workflow_template", session_id, params, user) do
    case session_id do
      "new" ->
        # Create new workflow template session
        with {:project_id, project_id} when not is_nil(project_id) <-
               {:project_id, params["project_id"]},
             {:project, project} when not is_nil(project) <-
               {:project, Projects.get_project(project_id)},
             {:content, content} when not is_nil(content) <-
               {:content, params["content"]} do
          workflow =
            if params["workflow_id"],
              do: Workflows.get_workflow(params["workflow_id"]),
              else: nil

          opts = extract_session_options("workflow_template", params)

          AiAssistant.create_workflow_session(
            project,
            workflow,
            user,
            content,
            opts
          )
        else
          {:project_id, nil} -> {:error, "project_id required"}
          {:project, nil} -> {:error, "project not found"}
          {:content, nil} -> {:error, "initial content required"}
        end

      _existing_id ->
        # Load existing session
        case AiAssistant.get_session!(session_id) do
          nil -> {:error, "session not found"}
          session -> {:ok, session}
        end
    end
  end

  defp authorize_session_access(session, user) do
    case session.session_type do
      "job_code" ->
        # User must have access to the job's project
        job = Jobs.get_job!(session.job_id)
        workflow = Workflows.get_workflow(job.workflow_id)
        project = Projects.get_project(workflow.project_id)
        project_user = Projects.get_project_user(project, user)

        Permissions.can(:workflows, :access_read, user, project_user)

      "workflow_template" ->
        # User must have access to the project
        project = Projects.get_project(session.project_id)
        project_user = Projects.get_project_user(project, user)

        Permissions.can(:workflows, :access_read, user, project_user)
    end
  end

  defp extract_session_options("job_code", params) do
    opts = []

    opts =
      if params["follow_run_id"] do
        Keyword.put(opts, :meta, %{"follow_run_id" => params["follow_run_id"]})
      else
        opts
      end

    opts
  end

  defp extract_session_options("workflow_template", params) do
    opts = []

    opts =
      if code = params["code"] do
        Keyword.put(opts, :code, code)
      else
        opts
      end

    opts
  end

  defp extract_message_options("job_code", params) do
    message_options = %{}

    message_options =
      if params["attach_code"] do
        Map.put(message_options, "code", true)
      else
        message_options
      end

    message_options =
      if params["attach_logs"] do
        Map.put(message_options, "log", true)
      else
        message_options
      end

    if map_size(message_options) > 0 do
      [meta: %{"message_options" => message_options}]
    else
      []
    end
  end

  defp extract_message_options("workflow_template", params) do
    opts = []

    opts =
      if code = params["code"] do
        Keyword.put(opts, :code, code)
      else
        opts
      end

    opts =
      if errors = params["errors"] do
        Keyword.put(opts, :errors, errors)
      else
        opts
      end

    opts
  end

  defp format_messages(messages) do
    Enum.map(messages, &format_message/1)
  end

  defp format_message(message) do
    %{
      id: message.id,
      content: message.content,
      code: message.code,
      role: to_string(message.role),
      status: to_string(message.status),
      inserted_at: message.inserted_at,
      user_id: message.user_id
    }
  end

  defp format_changeset_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
  end

  defp get_resource_for_session_type("job_code", session) do
    {:ok, Jobs.get_job!(session.job_id)}
  end

  defp get_resource_for_session_type("workflow_template", session) do
    case session.project_id do
      nil -> {:error, "Project not found"}
      project_id -> {:ok, Projects.get_project(project_id)}
    end
  end

  defp format_session(session) do
    base = %{
      id: session.id,
      title: session.title,
      session_type: session.session_type,
      message_count: session.message_count || 0,
      updated_at: session.updated_at
    }

    case session.session_type do
      "job_code" ->
        format_job_code_session(base, session)

      "workflow_template" ->
        format_workflow_template_session(base, session)

      _ ->
        base
    end
  end

  defp format_job_code_session(base, session) do
    job = Jobs.get_job!(session.job_id)
    workflow = Workflows.get_workflow(job.workflow_id)

    Map.merge(base, %{
      job_name: job.name,
      workflow_name: workflow.name
    })
  end

  defp format_workflow_template_session(base, session) do
    project = session.project || Projects.get_project(session.project_id)

    workflow_name =
      if session.workflow_id do
        workflow = Workflows.get_workflow(session.workflow_id)
        workflow.name
      else
        nil
      end

    Map.merge(base, %{
      project_name: project.name,
      workflow_name: workflow_name
    })
  end
end
