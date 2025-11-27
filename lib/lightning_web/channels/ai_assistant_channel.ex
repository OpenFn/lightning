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
         {:parse_topic, {:ok, session_type, session_id}} <-
           {:parse_topic, parse_topic(rest)},
         {:session, {:ok, session}} <-
           {:session,
            load_or_create_session(session_type, session_id, params, user)},
         :ok <- validate_session_type(session, session_type),
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

      {:parse_topic, {:error, :invalid_topic}} ->
        {:error, %{reason: "invalid topic format"}}

      {:session, {:error, reason}} ->
        {:error, %{reason: reason}}

      {:error, :session_type_mismatch} ->
        {:error, %{reason: "session type mismatch"}}

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

    {:ok, _user} = AiAssistant.mark_disclaimer_read(user)
    {:reply, {:ok, %{success: true}}, socket}
  end

  @impl true
  def handle_in("update_context", params, socket) do
    session = socket.assigns.session
    session_type = socket.assigns.session_type

    require Logger

    Logger.debug("""
    [AiAssistantChannel] update_context request
    Session type: #{session_type}
    Session ID: #{session.id}
    Params: #{inspect(params)}
    """)

    # Only job_code sessions can update context
    if session_type == "job_code" do
      # Extract updated job context
      job_body = params["job_body"]
      job_adaptor = params["job_adaptor"]
      job_name = params["job_name"]

      # Build updated context for meta
      # Preserve existing meta and update runtime_context
      updated_meta =
        (session.meta || %{})
        |> Map.put("runtime_context", %{
          "job_body" => job_body,
          "job_adaptor" => job_adaptor,
          "job_name" => job_name,
          "updated_at" => DateTime.utc_now() |> DateTime.to_iso8601()
        })

      # Update session in database with new meta
      case session
           |> Ecto.Changeset.change(%{meta: updated_meta})
           |> Lightning.Repo.update() do
        {:ok, updated_session} ->
          # Update session's virtual fields with new context
          updated_session =
            updated_session
            |> AiAssistant.put_expression_and_adaptor(
              job_body || session.expression || "",
              job_adaptor || "@openfn/language-common@latest"
            )

          # Update socket assigns with new context
          socket = assign(socket, session: updated_session)

          Logger.info("""
          [AiAssistantChannel] Context updated successfully
          Session ID: #{session.id}
          Job name: #{job_name}
          Job adaptor: #{job_adaptor}
          Job body length: #{if job_body, do: byte_size(job_body), else: 0}
          """)

          {:reply, {:ok, %{success: true}}, socket}

        {:error, changeset} ->
          Logger.error(
            "[AiAssistantChannel] Failed to update context: #{inspect(changeset.errors)}"
          )

          {:reply, {:error, %{reason: "Failed to persist context update"}},
           socket}
      end
    else
      Logger.warning(
        "[AiAssistantChannel] update_context called on non-job_code session: #{session_type}"
      )

      {:reply,
       {:error,
        %{reason: "Context updates only supported for job_code sessions"}},
       socket}
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

    # Build options with workflow filter for workflow_template sessions
    # This matches the legacy editor behavior where sessions are scoped by workflow
    opts = [offset: offset, limit: limit]

    opts =
      if session_type == "workflow_template" do
        # Extract workflow from session or unsaved_workflow meta
        workflow = get_workflow_for_session(session)

        Logger.debug("""
        [AiAssistantChannel] Filtering sessions by workflow
        Session workflow_id: #{inspect(session.workflow_id)}
        Session unsaved_workflow: #{inspect(session.meta["unsaved_workflow"])}
        Extracted workflow: #{inspect(workflow && workflow.id)}
        """)

        Keyword.put(opts, :workflow, workflow)
      else
        opts
      end

    with {:ok, resource} <- get_resource_for_session_type(session_type, session),
         %{sessions: sessions, pagination: pagination} <-
           AiAssistant.list_sessions(resource, :desc, opts) do
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

  defp validate_session_type(session, requested_type) do
    if session.session_type == requested_type do
      :ok
    else
      Logger.error("""
      Session type mismatch:
        Session ID: #{session.id}
        Session type in DB: #{session.session_type}
        Requested type in topic: #{requested_type}
      """)

      {:error, :session_type_mismatch}
    end
  end

  defp load_or_create_session("job_code", session_id, params, user) do
    case session_id do
      "new" ->
        # Create new job code session
        with {:job_id, job_id} when not is_nil(job_id) <-
               {:job_id, params["job_id"]},
             {:content, content} when not is_nil(content) <-
               {:content, params["content"]} do
          # Check if job exists in database
          case Jobs.get_job(job_id) do
            {:ok, job} ->
              # Job exists in database - use normal flow
              opts = extract_session_options("job_code", params)
              AiAssistant.create_session(job, user, content, opts)

            {:error, :not_found} ->
              # Job doesn't exist in DB yet (unsaved in Y.Doc)
              # Create session with unsaved job data from params
              create_session_with_unsaved_job(params, user, content)
          end
        else
          {:job_id, nil} -> {:error, "job_id required"}
          {:content, nil} -> {:error, "initial content required"}
        end

      _existing_id ->
        # Load existing session
        case AiAssistant.get_session(session_id) do
          {:ok, session} ->
            # Enrich with job context (expression and adaptor)
            enriched_session =
              AiAssistant.enrich_session_with_job_context(session)

            {:ok, enriched_session}

          {:error, :not_found} ->
            {:error, "session not found"}
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
          # Try to load workflow from database if workflow_id provided
          workflow =
            if params["workflow_id"],
              do: Workflows.get_workflow(params["workflow_id"]),
              else: nil

          # If workflow_id provided but workflow not found in DB,
          # this is a create mode workflow (temporary ID)
          is_new_workflow = params["workflow_id"] && is_nil(workflow)

          # Extract base options
          base_opts = extract_session_options("workflow_template", params)
          base_meta = Keyword.get(base_opts, :meta, %{})

          # If this is a new workflow (create mode), store temporary workflow_id in meta
          opts =
            if is_new_workflow do
              meta =
                Map.merge(base_meta, %{
                  "unsaved_workflow" => %{
                    "id" => params["workflow_id"],
                    "is_new" => true
                  }
                })

              Keyword.put(base_opts, :meta, meta)
            else
              base_opts
            end

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
        case AiAssistant.get_session(session_id) do
          {:ok, session} -> {:ok, session}
          {:error, :not_found} -> {:error, "session not found"}
        end
    end
  end

  defp create_session_with_unsaved_job(params, user, content) do
    # Extract unsaved job data from params
    job_id = params["job_id"]
    job_name = params["job_name"]
    job_body = params["job_body"] || ""
    job_adaptor = params["job_adaptor"] || "@openfn/language-common@latest"
    workflow_id = params["workflow_id"]

    # Validate required unsaved job fields
    if is_nil(job_name) or is_nil(workflow_id) do
      {:error, "Please save the workflow before using AI Assistant for this job"}
    else
      # Store unsaved job data in meta
      unsaved_job_data = %{
        "id" => job_id,
        "name" => job_name,
        "body" => job_body,
        "adaptor" => job_adaptor,
        "workflow_id" => workflow_id
      }

      base_meta =
        extract_session_options("job_code", params) |> Keyword.get(:meta, %{})

      meta = Map.merge(base_meta, %{"unsaved_job" => unsaved_job_data})

      # Create session without job_id (it's nil in DB until job is saved)
      AiAssistant.create_session_for_unsaved_job(
        user,
        content,
        meta
      )
    end
  end

  defp authorize_session_access(%{session_type: "job_code"} = session, user) do
    authorize_job_code_session(session, user)
  end

  defp authorize_session_access(
         %{session_type: "workflow_template"} = session,
         user
       ) do
    authorize_workflow_template_session(session, user)
  end

  defp authorize_job_code_session(session, user) do
    unsaved_job = session.meta["unsaved_job"]

    cond do
      # Unsaved job - verify access through workflow_id in meta
      unsaved_job && unsaved_job["workflow_id"] ->
        check_workflow_access_by_id(
          unsaved_job["workflow_id"],
          user,
          :access_read
        )

      # Saved job - verify access through job
      session.job_id ->
        authorize_saved_job_session(session.job_id, user)

      # Fallback - shouldn't happen
      true ->
        :ok
    end
  end

  defp authorize_workflow_template_session(session, user) do
    unsaved_workflow = session.meta["unsaved_workflow"]

    cond do
      # Unsaved workflow - verify access through project_id
      unsaved_workflow && unsaved_workflow["id"] ->
        check_project_access(session.project_id, user, :access_write)

      # Saved workflow or project-level session - verify through project_id
      session.project_id ->
        check_project_access(session.project_id, user, :access_write)

      # Fallback for older sessions
      true ->
        :ok
    end
  end

  defp authorize_saved_job_session(job_id, user) do
    case Jobs.get_job(job_id) do
      {:ok, job} ->
        check_workflow_access_by_id(job.workflow_id, user, :access_read)

      {:error, :not_found} ->
        # Job was deleted
        :ok
    end
  end

  defp check_workflow_access_by_id(workflow_id, user, permission) do
    workflow = Workflows.get_workflow(workflow_id)
    project = Projects.get_project(workflow.project_id)
    project_user = Projects.get_project_user(project, user)
    Permissions.can(:workflows, permission, user, project_user)
  end

  defp check_project_access(project_id, user, permission) do
    project = Projects.get_project(project_id)
    project_user = Projects.get_project_user(project, user)
    Permissions.can(:workflows, permission, user, project_user)
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
    # Build message options with explicit true/false values
    # This ensures the AI query respects checkbox states
    message_options = %{
      "code" => params["attach_code"] == true,
      "log" => params["attach_logs"] == true
    }

    [meta: %{"message_options" => message_options}]
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
    changeset
    |> Ecto.Changeset.traverse_errors(fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
    |> flatten_association_errors()
  end

  # Flattens nested association errors into a flat structure for frontend.
  # Converts %{triggers: [%{type: ["error"]}]} to %{"triggers[0].type" => ["error"]}
  defp flatten_association_errors(errors) do
    Enum.reduce(errors, %{}, fn {key, value}, acc ->
      flatten_error_value(key, value, acc)
    end)
  end

  defp flatten_error_value(key, list, acc) when is_list(list) do
    if Enum.any?(list, &is_map/1) do
      flatten_nested_list_errors(key, list, acc)
    else
      # List of error messages (not nested objects)
      Map.put(acc, to_string(key), list)
    end
  end

  defp flatten_error_value(key, messages, acc) when is_list(messages) do
    Map.put(acc, to_string(key), messages)
  end

  defp flatten_error_value(key, value, acc) do
    Map.put(acc, to_string(key), value)
  end

  defp flatten_nested_list_errors(key, list, acc) do
    list
    |> Enum.with_index()
    |> Enum.reduce(acc, fn {item_errors, index}, inner_acc ->
      flatten_item_errors(key, item_errors, index, inner_acc)
    end)
  end

  defp flatten_item_errors(key, item_errors, index, acc) do
    Enum.reduce(item_errors, acc, fn {field, messages}, nested_acc ->
      flattened_key = "#{key}[#{index}].#{field}"
      Map.put(nested_acc, flattened_key, messages)
    end)
  end

  # Extracts the workflow for a workflow_template session
  # Returns nil for unsaved workflows (matching legacy editor behavior)
  defp get_workflow_for_session(session) do
    cond do
      # Check if this is an unsaved workflow (no workflow_id, or has unsaved_workflow meta)
      session.meta["unsaved_workflow"] ->
        # Unsaved workflow - return nil to match sessions without workflow_id
        nil

      # Session has a workflow_id - load it from database
      session.workflow_id ->
        Workflows.get_workflow(session.workflow_id)

      # No workflow associated
      true ->
        nil
    end
  end

  defp get_resource_for_session_type("job_code", session) do
    # Extract job_id from either the session or unsaved_job meta
    job_id =
      cond do
        session.job_id -> session.job_id
        session.meta["unsaved_job"] -> session.meta["unsaved_job"]["id"]
        true -> nil
      end

    if job_id do
      # Return the job_id for querying sessions
      # We'll query sessions by job_id directly, not by loading the Job struct
      {:ok, job_id}
    else
      {:error, "Job not found"}
    end
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
    cond do
      # Check for unsaved job data first
      session.meta["unsaved_job"] ->
        unsaved_job = session.meta["unsaved_job"]
        workflow = Workflows.get_workflow(unsaved_job["workflow_id"])

        Map.merge(base, %{
          job_name: unsaved_job["name"],
          workflow_name: workflow.name,
          is_unsaved: true
        })

      # Try to load job from database
      session.job_id ->
        case Jobs.get_job(session.job_id) do
          {:ok, job} ->
            workflow = Workflows.get_workflow(job.workflow_id)

            Map.merge(base, %{
              job_name: job.name,
              workflow_name: workflow.name
            })

          {:error, :not_found} ->
            # Job was deleted
            Map.merge(base, %{
              job_name: "[Deleted Job]",
              workflow_name: nil
            })
        end

      # No job data
      true ->
        Map.merge(base, %{
          job_name: "[Unknown Job]",
          workflow_name: nil
        })
    end
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
