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
  alias Lightning.AiAssistant.Limiter
  alias Lightning.Jobs
  alias Lightning.Policies.Permissions
  alias Lightning.Projects
  alias Lightning.Workflows
  alias LightningWeb.Channels.AiAssistantJSON

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
      Lightning.subscribe("ai_session:#{session.id}")

      # Broadcast new session creation to workflow channel so other users see it
      if session_id == "new" do
        broadcast_session_created(session, user)
      end

      {:ok,
       %{
         session_id: session.id,
         session_type: session_type,
         messages: format_messages(session.messages),
         has_read_disclaimer: AiAssistant.user_has_read_disclaimer?(user)
       },
       assign(socket,
         session_id: session.id,
         session_type: session_type,
         session: session,
         current_user: user
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
    project_id = get_project_id_from_session(session)

    if String.trim(content) != "" do
      limit_result = Limiter.validate_quota(project_id)

      handle_new_message_with_quota(
        session,
        user,
        content,
        limit_result,
        params,
        socket
      )
    else
      reply_validation_error("Message cannot be empty", socket)
    end
  end

  @impl true
  def handle_in("retry_message", %{"message_id" => message_id}, socket) do
    message = Lightning.Repo.get(Lightning.AiAssistant.ChatMessage, message_id)
    project_id = get_project_id_from_session(socket.assigns.session)

    if message && message.chat_session_id == socket.assigns.session_id do
      case Limiter.validate_quota(project_id) do
        :ok ->
          retry_message_with_quota(message, socket)

        {:error, _, %Lightning.Extensions.Message{text: text}} ->
          reply_limit_error(text, socket)
      end
    else
      reply_unauthorized_error("message not found or unauthorized", socket)
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

    is_job_code =
      Map.has_key?(params, "job_adaptor") && !is_nil(params["job_adaptor"])

    IO.inspect(is_job_code, label: "han:all")

    case is_job_code do
      true ->
        update_job_code_context(session, params, socket)

      false ->
        update_workflow_template_context(session, params, socket)

      _ ->
        {:reply,
         {:error,
          %{reason: "Context updates not supported for this session type"}},
         socket}
    end
  end

  @impl true
  def handle_in("list_sessions", params, socket) do
    session = socket.assigns.session
    session_type = socket.assigns.session_type

    offset = Map.get(params, "offset", 0)
    limit = Map.get(params, "limit", 20)

    opts = [offset: offset, limit: limit]

    opts =
      if session_type == "workflow_template" do
        workflow = get_workflow_for_session(session)
        Keyword.put(opts, :workflow, workflow)
      else
        opts
      end

    with {:ok, resource} <- get_resource_for_session_type(session_type, session),
         %{sessions: sessions, pagination: pagination} <-
           AiAssistant.list_sessions(resource, :desc, opts) do
      {:reply,
       {:ok,
        %{
          sessions: AiAssistantJSON.format_sessions(sessions),
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

  defp update_job_code_context(session, params, socket) do
    job_body = params["job_body"]
    job_adaptor = params["job_adaptor"]
    job_name = params["job_name"]

    # Fetch fresh session from DB to get current meta (including message_options)
    # This prevents race conditions where update_context overwrites message_options
    # set by a concurrent new_message call
    fresh_session =
      Lightning.Repo.get!(Lightning.AiAssistant.ChatSession, session.id)

    updated_meta =
      (fresh_session.meta || %{})
      |> Map.put("runtime_context", %{
        "job_body" => job_body,
        "job_adaptor" => job_adaptor,
        "job_name" => job_name,
        "updated_at" => DateTime.utc_now() |> DateTime.to_iso8601()
      })

    case fresh_session
         |> Ecto.Changeset.change(%{meta: updated_meta})
         |> Lightning.Repo.update() do
      {:ok, updated_session} ->
        updated_session =
          updated_session
          |> AiAssistant.put_expression_and_adaptor(
            job_body || session.expression || "",
            job_adaptor || "@openfn/language-common@latest"
          )

        socket = assign(socket, session: updated_session)

        {:reply, {:ok, %{success: true}}, socket}

      {:error, changeset} ->
        Logger.error(
          "[AiAssistantChannel] Failed to update job context: #{inspect(changeset.errors)}"
        )

        {:reply, {:error, %{reason: "Failed to persist context update"}}, socket}
    end
  end

  defp update_workflow_template_context(session, params, socket) do
    workflow_id = params["workflow_id"]

    if workflow_id do
      updated_meta =
        (session.meta || %{})
        |> Map.delete("unsaved_workflow")

      session
      |> Ecto.Changeset.change(%{
        workflow_id: workflow_id,
        meta: updated_meta
      })
      |> Lightning.Repo.update()
      |> case do
        {:ok, updated_session} ->
          {:reply, {:ok, %{success: true}},
           assign(socket, session: updated_session)}

        {:error, changeset} ->
          Logger.error(
            "[AiAssistantChannel] Failed to update workflow context: #{inspect(changeset.errors)}"
          )

          {:reply, {:error, %{reason: "Failed to persist context update"}},
           socket}
      end
    else
      {:reply, {:ok, %{success: true}}, socket}
    end
  end

  @impl true
  def handle_info(
        {:ai_assistant, :message_status_changed,
         %{status: {status, updated_session}, session_id: session_id}},
        socket
      ) do
    if socket.assigns.session_id == session_id do
      case status do
        :processing ->
          # Broadcast processing state so all users see loading indicator
          # and have their input blocked
          broadcast(socket, "message_processing", %{session_id: session_id})

        :success ->
          assistant_message =
            updated_session.messages
            |> Enum.reverse()
            |> Enum.find(fn msg -> msg.role == :assistant end)

          if assistant_message do
            # Broadcast to all users so everyone sees the assistant response
            broadcast(socket, "new_message", %{
              message: format_message(assistant_message)
            })
          end

        :error ->
          # Broadcast error state so all users can see and retry
          user_message =
            updated_session.messages
            |> Enum.reverse()
            |> Enum.find(fn msg -> msg.role == :user end)

          if user_message do
            broadcast(socket, "message_error", %{
              message_id: user_message.id,
              status: "error"
            })
          end

        :failed ->
          # Handle failed status (similar to error)
          user_message =
            updated_session.messages
            |> Enum.reverse()
            |> Enum.find(fn msg -> msg.role == :user end)

          if user_message do
            broadcast(socket, "message_error", %{
              message_id: user_message.id,
              status: "failed"
            })
          end
      end
    end

    {:noreply, socket}
  end

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
        with {:job_id, job_id} when not is_nil(job_id) <-
               {:job_id, params["job_id"]},
             {:content, content} when not is_nil(content) <-
               {:content, params["content"]} do
          case Jobs.get_job(job_id) do
            {:ok, job} ->
              opts = extract_session_options("job_code", params)
              AiAssistant.create_session(job, user, content, opts)

            {:error, :not_found} ->
              create_session_with_unsaved_job(params, user, content)
          end
        else
          {:job_id, nil} -> {:error, "job_id required"}
          {:content, nil} -> {:error, "initial content required"}
        end

      _existing_id ->
        case AiAssistant.get_session(session_id) do
          {:ok, session} ->
            session =
              if params["follow_run_id"] do
                updated_meta =
                  Map.put(
                    session.meta || %{},
                    "follow_run_id",
                    params["follow_run_id"]
                  )

                session
                |> Ecto.Changeset.change(%{meta: updated_meta})
                |> Lightning.Repo.update!()
              else
                session
              end

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

          is_new_workflow = params["workflow_id"] && is_nil(workflow)

          base_opts = extract_session_options("workflow_template", params)
          base_meta = Keyword.get(base_opts, :meta, %{})

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

          job = params["job_id"] && Jobs.get_job!(params["job_id"])

          AiAssistant.create_workflow_session(
            project,
            job,
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
        case AiAssistant.get_session(session_id) do
          {:ok, session} -> {:ok, session}
          {:error, :not_found} -> {:error, "session not found"}
        end
    end
  end

  defp create_session_with_unsaved_job(params, user, content) do
    job_id = params["job_id"]
    job_name = params["job_name"]
    job_body = params["job_body"] || ""
    job_adaptor = params["job_adaptor"] || "@openfn/language-common@latest"
    workflow_id = params["workflow_id"]

    if is_nil(job_name) or is_nil(workflow_id) do
      {:error, "Please save the workflow before using AI Assistant for this job"}
    else
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
      unsaved_job && unsaved_job["workflow_id"] ->
        check_workflow_access_by_id(
          unsaved_job["workflow_id"],
          user,
          :access_read
        )

      session.job_id ->
        authorize_saved_job_session(session.job_id, user)

      true ->
        :ok
    end
  end

  defp authorize_workflow_template_session(session, user) do
    unsaved_workflow = session.meta["unsaved_workflow"]

    cond do
      unsaved_workflow && unsaved_workflow["id"] ->
        check_project_access(session.project_id, user, :access_write)

      session.project_id ->
        check_project_access(session.project_id, user, :access_write)

      true ->
        :ok
    end
  end

  defp authorize_saved_job_session(job_id, user) do
    case Jobs.get_job(job_id) do
      {:ok, job} ->
        check_workflow_access_by_id(job.workflow_id, user, :access_read)

      {:error, :not_found} ->
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
    meta = %{}

    meta =
      if params["follow_run_id"] do
        Map.put(meta, "follow_run_id", params["follow_run_id"])
      else
        meta
      end

    # Include message_options for the initial message (attach_io_data, step_id, etc.)
    meta =
      if params["attach_io_data"] || params["step_id"] || params["attach_code"] ||
           params["attach_logs"] do
        Map.put(meta, "message_options", build_message_options(params))
      else
        meta
      end

    if map_size(meta) > 0 do
      [meta: meta]
    else
      []
    end
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

  defp extract_message_options(%{"job_id" => _job_id} = params) do
    [meta: %{"message_options" => build_message_options(params)}]
  end

  defp extract_message_options(%{"code" => code} = _params) do
    if code do
      [code: code]
    else
      []
    end
  end

  defp extract_message_options(_params) do
    []
  end

  defp build_message_options(params) do
    %{
      "code" => params["attach_code"] == true,
      "log" => params["attach_logs"] == true,
      "attach_io_data" => params["attach_io_data"] == true,
      "step_id" => params["step_id"]
    }
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
      user_id: message.user_id,
      user: format_user(message.user),
      job_id: message.job_id
    }
  end

  defp format_user(nil), do: nil

  defp format_user(%Ecto.Association.NotLoaded{}), do: nil

  defp format_user(user) do
    %{
      id: user.id,
      first_name: user.first_name,
      last_name: user.last_name
    }
  end

  @doc """
  Formats Ecto changeset errors into a flat map structure for API responses.

  Converts nested changeset errors into a user-friendly format with interpolated
  values and flattened keys for nested associations.

  ## Examples

      iex> changeset = %Ecto.Changeset{errors: [content: {"can't be blank", []}]}
      iex> format_changeset_errors(changeset)
      %{"content" => ["can't be blank"]}

      iex> changeset = %Ecto.Changeset{
      ...>   errors: [
      ...>     content: {"should be at least %{count} character(s)", [count: 5]}
      ...>   ]
      ...> }
      iex> format_changeset_errors(changeset)
      %{"content" => ["should be at least 5 character(s)"]}

  ## Nested Association Errors

  For nested associations (e.g., has_many relationships), errors are flattened
  using bracket notation:

      %{"jobs[0].name" => ["can't be blank"], "jobs[1].adaptor" => ["is invalid"]}

  ## Parameters

    * `changeset` - An Ecto.Changeset with validation errors

  ## Returns

  A map with string keys (field names) and list values (error messages).
  Returns an empty map if the changeset has no errors.
  """
  def format_changeset_errors(changeset) do
    changeset
    |> Ecto.Changeset.traverse_errors(fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
    |> flatten_association_errors()
  end

  defp flatten_association_errors(errors) do
    Enum.reduce(errors, %{}, fn {key, value}, acc ->
      flatten_error_value(key, value, acc)
    end)
  end

  @doc false
  def flatten_error_value(key, list, acc) when is_list(list) do
    if Enum.any?(list, &is_map/1) do
      flatten_nested_list_errors(key, list, acc)
    else
      Map.put(acc, to_string(key), list)
    end
  end

  @doc false
  def flatten_error_value(key, value, acc) do
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

  defp get_workflow_for_session(session) do
    cond do
      session.meta["unsaved_workflow"] ->
        nil

      session.workflow_id ->
        Workflows.get_workflow(session.workflow_id)

      true ->
        nil
    end
  end

  defp get_resource_for_session_type("job_code", session) do
    job_id =
      cond do
        session.job_id -> session.job_id
        session.meta["unsaved_job"] -> session.meta["unsaved_job"]["id"]
        true -> nil
      end

    if job_id do
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

  defp get_project_id_from_session(session) do
    cond do
      session.project_id ->
        session.project_id

      session.job_id ->
        case Jobs.get_job(session.job_id) do
          {:ok, job} ->
            workflow = Workflows.get_workflow(job.workflow_id)
            workflow.project_id

          {:error, :not_found} ->
            get_project_id_from_unsaved_job(session)
        end

      true ->
        get_project_id_from_unsaved_job(session)
    end
  end

  defp get_project_id_from_unsaved_job(session) do
    if session.meta["unsaved_job"] do
      workflow_id = session.meta["unsaved_job"]["workflow_id"]
      workflow = Workflows.get_workflow(workflow_id)
      workflow.project_id
    else
      nil
    end
  end

  # Private helpers for handle_in("new_message")

  defp handle_new_message_with_quota(
         session,
         user,
         content,
         limit_result,
         params,
         socket
       ) do
    job = params["job_id"] && Jobs.get_job!(params["job_id"])

    message_attrs = build_message_attrs(user, job, content, limit_result)
    opts = extract_message_options(params)

    case AiAssistant.save_message(session, message_attrs, opts) do
      {:ok, updated_session} ->
        message = find_user_message(updated_session.messages, content)

        # Broadcast the user message to all subscribers so other users see it
        broadcast(socket, "user_message", %{message: format_message(message)})

        response = build_message_response(message, limit_result)
        {:reply, {:ok, response}, socket}

      {:error, changeset} ->
        errors = format_changeset_errors(changeset)
        {:reply, {:error, %{type: "validation_error", errors: errors}}, socket}
    end
  end

  defp build_message_attrs(user, job, content, limit_result) do
    base_attrs = %{role: :user, content: content, user: user, job: job}

    case limit_result do
      :ok -> base_attrs
      {:error, _, _} -> Map.put(base_attrs, :status, :error)
    end
  end

  defp find_user_message(messages, content) do
    # Find the LAST (most recently added) user message with this content
    # This ensures we return the newly created message, not an older one
    # with the same content
    messages
    |> Enum.reverse()
    |> Enum.find(fn msg ->
      msg.role == :user && msg.content == content
    end)
  end

  defp build_message_response(message, limit_result) do
    base_response = %{message: format_message(message)}

    case limit_result do
      :ok ->
        base_response

      {:error, _, %Lightning.Extensions.Message{text: text}} ->
        Map.put(base_response, :error, text)
    end
  end

  # Private helpers for handle_in("retry_message")

  defp retry_message_with_quota(message, socket) do
    case AiAssistant.retry_message(message) do
      {:ok, {updated_message, _oban_job}} ->
        # Broadcast status change to all users so retry button hides for everyone
        broadcast(socket, "message_status_changed", %{
          message_id: updated_message.id,
          status: to_string(updated_message.status)
        })

        {:reply, {:ok, %{message: format_message(updated_message)}}, socket}

      {:error, changeset} ->
        errors = format_changeset_errors(changeset)
        {:reply, {:error, %{type: "validation_error", errors: errors}}, socket}
    end
  end

  # Private helpers for error replies

  defp reply_validation_error(message, socket) do
    {:reply, {:error, %{type: "validation_error", errors: %{base: [message]}}},
     socket}
  end

  defp reply_limit_error(message, socket) do
    {:reply, {:error, %{type: "limit_error", errors: %{base: [message]}}},
     socket}
  end

  defp reply_unauthorized_error(message, socket) do
    {:reply, {:error, %{type: "unauthorized", errors: %{base: [message]}}},
     socket}
  end

  # Broadcasts session creation to the workflow channel so other users see the new session
  defp broadcast_session_created(session, user) do
    workflow_id = get_workflow_id_for_session(session)

    if workflow_id do
      # Preload associations needed for formatting
      # Note: For job_code sessions, workflow is accessed via job.workflow
      session =
        Lightning.Repo.preload(
          session,
          [job: [:workflow], workflow: [], project: []],
          force: true
        )

      formatted_session =
        AiAssistantJSON.format_session(session)
        |> Map.put(:user, format_session_user(user))

      LightningWeb.Endpoint.broadcast(
        "workflow:collaborate:#{workflow_id}",
        "ai_session_created",
        %{session: formatted_session}
      )
    end
  end

  defp get_workflow_id_for_session(session) do
    cond do
      session.workflow_id ->
        session.workflow_id

      session.job_id ->
        case Jobs.get_job(session.job_id) do
          {:ok, job} -> job.workflow_id
          _ -> nil
        end

      session.meta["unsaved_job"] ->
        session.meta["unsaved_job"]["workflow_id"]

      session.meta["unsaved_workflow"] ->
        session.meta["unsaved_workflow"]["id"]

      true ->
        nil
    end
  end

  defp format_session_user(user) do
    %{
      id: user.id,
      first_name: user.first_name,
      last_name: user.last_name
    }
  end
end
