defmodule LightningWeb.WorkflowChannel do
  @moduledoc """
  Phoenix Channel for handling binary Yjs collaboration messages.

  Unlike LiveView events, Phoenix Channels properly support binary data
  transmission without JSON serialization.
  """
  use LightningWeb, :channel

  import Ecto.Query, only: [from: 2]

  alias Lightning.Collaborate
  alias Lightning.Collaboration.Session
  alias Lightning.Collaboration.Utils
  alias Lightning.Policies.Permissions
  alias Lightning.Repo
  alias Lightning.VersionControl
  alias Lightning.Workflows.Job
  alias Lightning.Workflows.Snapshot
  alias Lightning.Workflows.Workflow
  alias Lightning.WorkOrders
  alias LightningWeb.Channels.WorkflowJSON

  require Logger

  @impl true
  def join(
        "workflow:collaborate:" <> rest = topic,
        %{"project_id" => project_id, "action" => action},
        socket
      ) do
    # Room formats:
    # - "workflow_id" → latest (collaborative editing room)
    # - "workflow_id:vN" → specific version N (isolated snapshot viewing)
    {workflow_id, version} =
      case String.split(rest, ":v", parts: 2) do
        [wf_id, version] -> {wf_id, version}
        [wf_id] -> {wf_id, nil}
      end

    with {:user, user} when not is_nil(user) <-
           {:user, socket.assigns[:current_user]},
         {:project, %_{} = project} <-
           {:project, Lightning.Projects.get_project(project_id)},
         {:workflow, {:ok, workflow}} <-
           {:workflow,
            load_workflow(action, workflow_id, project, user, version)} do
      Logger.info("""
      Joining workflow collaboration:
        workflow_id: #{workflow_id}
        version: #{inspect(version)}
        room: #{topic}
        is_latest: #{is_nil(version)}
      """)

      {:ok, session_pid} =
        Collaborate.start(
          user: user,
          workflow: workflow,
          room_topic: topic
        )

      project_user = Lightning.Projects.get_project_user(project, user)

      # Subscribe to work order events for this workflow's project
      WorkOrders.subscribe(project.id)

      Phoenix.PubSub.subscribe(
        Lightning.PubSub,
        "workflow:collaborate:#{workflow_id}"
      )

      {:ok,
       assign(socket,
         workflow_id: workflow_id,
         collaboration_topic: topic,
         workflow: workflow,
         project: project,
         session_pid: session_pid,
         project_user: project_user,
         snapshot_version: version
       )}
    else
      {:user, nil} -> {:error, %{reason: "unauthorized"}}
      {:project, nil} -> {:error, %{reason: "project not found"}}
      {:workflow, {:error, reason}} -> {:error, %{reason: reason}}
    end
  end

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
  def handle_in("request_project_adaptors", _payload, socket) do
    project = socket.assigns.project

    async_task(socket, "request_project_adaptors", fn ->
      project_adaptor_names =
        from(j in Job,
          join: w in assoc(j, :workflow),
          where: w.project_id == ^project.id,
          select: j.adaptor,
          distinct: true
        )
        |> Lightning.Repo.all()
        |> Enum.sort()

      all_adaptors = Lightning.AdaptorRegistry.all()

      project_adaptors =
        all_adaptors
        |> Enum.filter(fn adaptor ->
          Enum.any?(project_adaptor_names, fn used_adaptor ->
            String.starts_with?(used_adaptor, adaptor.name)
          end)
        end)

      %{
        project_adaptors: project_adaptors,
        all_adaptors: all_adaptors
      }
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
        |> WorkflowJSON.render()

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
      # For unsaved workflows (action="new"), lock_version is nil and the workflow
      # doesn't exist in the database yet. Use the in-memory workflow in that case.
      # For saved workflows, always fetch fresh from DB to get the actual latest
      # lock_version (socket.assigns.workflow could be stale).
      fresh_workflow =
        if is_nil(workflow.lock_version) do
          workflow
        else
          Lightning.Workflows.get_workflow(workflow.id)
        end

      project_repo_connection =
        VersionControl.get_repo_connection_for_project(project.id)

      webhook_auth_methods =
        Lightning.WebhookAuthMethods.list_for_project(project)

      workflow_template =
        Lightning.WorkflowTemplates.get_template_by_workflow_id(workflow.id)

      %{
        user: render_user_context(user),
        project: render_project_context(project),
        config: render_config_context(),
        permissions: render_permissions(user, project_user),
        latest_snapshot_lock_version:
          (fresh_workflow && fresh_workflow.lock_version) ||
            workflow.lock_version,
        project_repo_connection: render_repo_connection(project_repo_connection),
        webhook_auth_methods: render_webhook_auth_methods(webhook_auth_methods),
        workflow_template: render_workflow_template(workflow_template)
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

  @impl true
  def handle_in("request_history", %{"run_id" => run_id}, socket) do
    workflow = socket.assigns.workflow

    async_task(socket, "request_history", fn ->
      history = get_workflow_run_history(workflow.id, run_id)
      %{history: history}
    end)
  end

  def handle_in("request_history", _params, socket) do
    # No run_id provided - fetch top 20
    handle_in("request_history", %{"run_id" => nil}, socket)
  end

  @impl true
  def handle_in(
        "request_run_steps",
        %{"run_id" => run_id},
        %{assigns: %{project: project}} = socket
      ) do
    async_task(socket, "request_run_steps", fn ->
      case Lightning.Invocation.get_run_with_steps(run_id) do
        nil ->
          {:error, %{reason: "run_not_found"}}

        run ->
          # Verify run belongs to this project's workflows
          if run.work_order.workflow.project_id == project.id do
            {:ok, format_run_steps_for_client(run)}
          else
            {:error, %{reason: "unauthorized"}}
          end
      end
    end)
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
      # Broadcast the new lock_version to all users in the channel
      # so they can update their latestSnapshotLockVersion in SessionContextStore
      broadcast_from!(socket, "workflow_saved", %{
        latest_snapshot_lock_version: workflow.lock_version
      })

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
  def handle_in("save_and_sync", params, socket)
      when not is_map_key(params, "commit_message") do
    {:reply,
     {:error,
      %{
        errors: %{commit_message: ["can't be blank"]},
        type: "validation_error"
      }}, socket}
  end

  @impl true
  def handle_in("save_and_sync", %{"commit_message" => commit_message}, socket) do
    session_pid = socket.assigns.session_pid
    user = socket.assigns.current_user
    project = socket.assigns.project

    with :ok <- authorize_edit_workflow(socket),
         {:ok, workflow} <- Session.save_workflow(session_pid, user),
         repo_connection when not is_nil(repo_connection) <-
           VersionControl.get_repo_connection_for_project(project.id),
         :ok <- VersionControl.initiate_sync(repo_connection, commit_message) do
      broadcast_from!(socket, "workflow_saved", %{
        latest_snapshot_lock_version: workflow.lock_version
      })

      {:reply,
       {:ok,
        %{
          saved_at: workflow.updated_at,
          lock_version: workflow.lock_version,
          repo: repo_connection.repo
        }}, socket}
    else
      nil ->
        {:reply,
         {:error,
          %{
            errors: %{base: ["No GitHub connection configured for this project"]},
            type: "github_sync_error"
          }}, socket}

      {:error, reason} when is_binary(reason) ->
        {:reply,
         {:error,
          %{
            errors: %{base: [reason]},
            type: "github_sync_error"
          }}, socket}

      error ->
        workflow_error_reply(socket, error)
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

    validated_params = ensure_unique_name(params, project)

    {:reply, {:ok, %{workflow: validated_params}}, socket}
  end

  @impl true
  def handle_in("request_versions", _payload, socket) do
    Logger.info("====== RECEIVED request_versions ======")
    workflow = socket.assigns.workflow
    Logger.info("Workflow ID: #{workflow.id}")

    async_task(socket, "request_versions", fn ->
      Logger.info("Inside async_task for request_versions")

      # For unsaved workflows (action="new"), there are no versions to show.
      # Return empty list instead of crashing.
      if is_nil(workflow.lock_version) do
        Logger.info("Workflow is unsaved, returning empty versions list")
        %{versions: []}
      else
        fresh_workflow = Lightning.Workflows.get_workflow(workflow.id)
        latest_lock_version = fresh_workflow.lock_version

        snapshots = Lightning.Workflows.Snapshot.get_all_for(workflow)

        Logger.info("Fetching versions for workflow #{workflow.id}")
        Logger.info("Found #{length(snapshots)} snapshots")
        Logger.info("Socket workflow lock_version: #{workflow.lock_version}")
        Logger.info("Fresh workflow lock_version: #{latest_lock_version}")

        versions =
          snapshots
          |> Enum.map(fn snapshot ->
            %{
              lock_version: snapshot.lock_version,
              inserted_at: snapshot.inserted_at,
              is_latest: snapshot.lock_version == latest_lock_version
            }
          end)
          |> Enum.sort_by(fn v ->
            {if(v.is_latest, do: 0, else: 1), -v.lock_version}
          end)

        Logger.info("Mapped versions: #{inspect(versions)}")

        %{versions: versions}
      end
    end)
  end

  @impl true
  def handle_in(
        "request_trigger_auth_methods",
        %{"trigger_id" => trigger_id},
        socket
      ) do
    Logger.debug("""
    WorkflowChannel: request_trigger_auth_methods
      trigger_id: #{trigger_id}
    """)

    async_task(socket, "request_trigger_auth_methods", fn ->
      trigger = Lightning.Repo.get!(Lightning.Workflows.Trigger, trigger_id)

      webhook_auth_methods_query =
        from(wam in Lightning.Workflows.WebhookAuthMethod,
          where: is_nil(wam.scheduled_deletion),
          order_by: wam.name
        )

      trigger_with_auth =
        Lightning.Repo.preload(trigger,
          webhook_auth_methods: webhook_auth_methods_query
        )

      %{
        trigger_id: trigger_id,
        webhook_auth_methods:
          render_webhook_auth_methods(trigger_with_auth.webhook_auth_methods)
      }
    end)
  end

  @impl true
  def handle_in(
        "update_trigger_auth_methods",
        %{"trigger_id" => trigger_id, "auth_method_ids" => auth_method_ids},
        socket
      ) do
    Logger.debug("""
    WorkflowChannel: update_trigger_auth_methods
      trigger_id: #{trigger_id}
      auth_method_ids: #{inspect(auth_method_ids)}
    """)

    with :ok <- authorize_edit_workflow(socket),
         trigger <- Lightning.Repo.get!(Lightning.Workflows.Trigger, trigger_id),
         :ok <- verify_trigger_in_workflow(trigger, socket.assigns.workflow_id),
         auth_methods <-
           fetch_auth_methods(auth_method_ids, socket.assigns.project),
         {:ok, updated_trigger} <-
           Lightning.WebhookAuthMethods.update_trigger_auth_methods(
             trigger,
             auth_methods,
             actor: socket.assigns.current_user
           ) do
      # Broadcast update to all collaborators in the room (including sender)
      broadcast!(socket, "trigger_auth_methods_updated", %{
        trigger_id: trigger_id,
        webhook_auth_methods:
          render_webhook_auth_methods(updated_trigger.webhook_auth_methods)
      })

      {:reply, {:ok, %{success: true}}, socket}
    else
      {:error, %{type: "unauthorized", message: message}} ->
        {:reply, {:error, %{reason: message}}, socket}

      {:error, :wrong_workflow} ->
        {:reply, {:error, %{reason: "trigger does not belong to this workflow"}},
         socket}

      {:error, %Ecto.Changeset{} = changeset} ->
        errors =
          Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
            Enum.reduce(opts, msg, fn {key, value}, acc ->
              String.replace(acc, "%{#{key}}", to_string(value))
            end)
          end)

        {:reply, {:error, %{reason: "validation failed", errors: errors}},
         socket}

      error ->
        Logger.error("Failed to update trigger auth methods: #{inspect(error)}")
        {:reply, {:error, %{reason: "internal error"}}, socket}
    end
  end

  @impl true
  def handle_in("publish_template", params, socket) do
    with :ok <- authorize_publish_template(socket),
         {:ok, template} <- publish_template(socket, params) do
      broadcast_from!(socket, "template_updated", %{
        workflow_template: render_workflow_template(template)
      })

      {:reply, {:ok, %{template: render_workflow_template(template)}}, socket}
    else
      error -> workflow_error_reply(socket, error)
    end
  end

  @impl true
  def handle_info({:yjs, chunk}, socket) do
    push(socket, "yjs", {:binary, chunk})
    {:noreply, socket}
  end

  @impl true
  def handle_info({:async_reply, socket_ref, event, reply}, socket) do
    handle_async_event(event, socket_ref, reply)
    {:noreply, socket}
  end

  @impl true
  def handle_info(%{event: "presence_diff", payload: _diff}, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_info(%{event: "credentials_updated", payload: credentials}, socket) do
    # Forward credential updates from PubSub to connected channel clients
    push(socket, "credentials_updated", credentials)
    {:noreply, socket}
  end

  @impl true
  def handle_info(
        %{event: "webhook_auth_methods_updated", payload: webhook_auth_methods},
        socket
      ) do
    push(socket, "webhook_auth_methods_updated", webhook_auth_methods)
    {:noreply, socket}
  end

  @impl true
  def handle_info(
        {:DOWN, _ref, :process, _pid, _reason},
        socket
      ) do
    {:stop, {:error, "remote process crash"}, socket}
  end

  @impl true
  def handle_info(
        %WorkOrders.Events.WorkOrderCreated{
          work_order: wo,
          project_id: _project_id
        },
        socket
      ) do
    if wo.workflow_id == socket.assigns.workflow_id do
      formatted_wo = format_work_order_for_history(wo)

      push(socket, "history_updated", %{
        work_order: formatted_wo,
        action: "created"
      })
    end

    {:noreply, socket}
  end

  @impl true
  def handle_info(
        %WorkOrders.Events.WorkOrderUpdated{work_order: wo},
        socket
      ) do
    if wo.workflow_id == socket.assigns.workflow_id do
      formatted_wo = format_work_order_for_history(wo)

      push(socket, "history_updated", %{
        work_order: formatted_wo,
        action: "updated"
      })
    end

    {:noreply, socket}
  end

  @impl true
  def handle_info(
        %WorkOrders.Events.RunCreated{run: run, project_id: _project_id},
        socket
      ) do
    case WorkOrders.get(run.work_order_id, include: [:workflow]) do
      %{workflow_id: workflow_id}
      when workflow_id == socket.assigns.workflow_id ->
        formatted_run = format_run_for_history(run)

        push(socket, "history_updated", %{
          run: formatted_run,
          work_order_id: run.work_order_id,
          action: "run_created"
        })

      _ ->
        :ok
    end

    {:noreply, socket}
  end

  @impl true
  def handle_info(
        %WorkOrders.Events.RunUpdated{run: run},
        socket
      ) do
    case WorkOrders.get(run.work_order_id, include: [:workflow]) do
      %{workflow_id: workflow_id}
      when workflow_id == socket.assigns.workflow_id ->
        formatted_run = format_run_for_history(run)

        push(socket, "history_updated", %{
          run: formatted_run,
          work_order_id: run.work_order_id,
          action: "run_updated"
        })

      _ ->
        :ok
    end

    {:noreply, socket}
  end

  @impl true
  def handle_out(event, payload, socket) do
    push(socket, event, payload)
    {:noreply, socket}
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

  defp handle_async_event("request_run_steps", socket_ref, reply) do
    unwrapped_reply = unwrap_run_steps_reply(reply)
    reply(socket_ref, unwrapped_reply)
  end

  defp handle_async_event(event, socket_ref, reply)
       when event in [
              "request_adaptors",
              "request_project_adaptors",
              "request_credentials",
              "request_current_user",
              "get_context",
              "request_history",
              "request_versions",
              "request_trigger_auth_methods"
            ] do
    reply(socket_ref, reply)
  end

  defp handle_async_event(event, _socket_ref, _reply) do
    Logger.warning("Unhandled async reply for event: #{event}")
  end

  defp unwrap_run_steps_reply({:ok, {:ok, data}}), do: {:ok, data}
  defp unwrap_run_steps_reply({:ok, {:error, reason}}), do: {:error, reason}
  defp unwrap_run_steps_reply(error), do: error

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
      support_user: user.support_user,
      inserted_at: user.inserted_at
    }
  end

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

    can_run =
      Permissions.can?(
        :project_users,
        :run_workflow,
        user,
        project_user
      )

    can_write_webhook_auth =
      Permissions.can?(
        :project_users,
        :write_webhook_auth_method,
        user,
        project_user
      )

    %{
      can_edit_workflow: can_edit,
      can_run_workflow: can_run,
      can_write_webhook_auth_method: can_write_webhook_auth
    }
  end

  defp render_repo_connection(nil), do: nil

  defp render_repo_connection(repo_connection) do
    %{
      id: repo_connection.id,
      repo: repo_connection.repo,
      branch: repo_connection.branch,
      github_installation_id: repo_connection.github_installation_id
    }
  end

  defp render_webhook_auth_methods(methods) do
    Enum.map(methods, fn method ->
      %{
        id: method.id,
        name: method.name,
        auth_type: method.auth_type
      }
    end)
  end

  defp render_workflow_template(nil), do: nil

  defp render_workflow_template(template) do
    Map.take(template, [
      :id,
      :name,
      :description,
      :code,
      :positions,
      :tags,
      :workflow_id
    ])
  end

  defp publish_template(socket, params) do
    workflow = socket.assigns.workflow
    template_params = Map.put(params, "workflow_id", workflow.id)

    case Lightning.WorkflowTemplates.create_template(template_params) do
      {:ok, template} -> {:ok, template}
      {:error, changeset} -> {:error, changeset}
    end
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

  defp flatten_error_value(key, list, acc) when is_list(list) do
    if Enum.any?(list, &is_map/1) do
      flatten_nested_list_errors(key, list, acc)
    else
      Map.put(acc, to_string(key), list)
    end
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

  defp authorize_publish_template(socket) do
    user = socket.assigns.current_user
    project = socket.assigns.project

    case Permissions.can(:project_users, :publish_template, user, project) do
      :ok ->
        :ok

      {:error, :unauthorized} ->
        {:error,
         %{
           type: "unauthorized",
           message: "You don't have permission to publish templates"
         }}
    end
  end

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

  defp verify_trigger_in_workflow(trigger, workflow_id) do
    if trigger.workflow_id == workflow_id do
      :ok
    else
      {:error, :wrong_workflow}
    end
  end

  defp fetch_auth_methods(ids, project) when is_list(ids) do
    Lightning.WebhookAuthMethods.list_for_project(project)
    |> Enum.filter(fn method -> method.id in ids end)
  end

  defp fetch_auth_methods(_ids, _project), do: []

  defp load_workflow("edit", workflow_id, project, user, version)
       when is_binary(version) do
    Logger.info("Loading workflow snapshot version: #{version}")

    case Integer.parse(version) do
      {lock_version, ""} ->
        case Snapshot.get_by_version(workflow_id, lock_version) do
          nil ->
            {:error, "snapshot version #{version} not found"}

          snapshot ->
            trigger_ids =
              snapshot.triggers
              |> Enum.map(& &1.id)
              |> Enum.map(&Ecto.UUID.dump!/1)

            trigger_auth_methods =
              from(twam in "trigger_webhook_auth_methods",
                where: twam.trigger_id in ^trigger_ids,
                join: wam in Lightning.Workflows.WebhookAuthMethod,
                on: twam.webhook_auth_method_id == wam.id,
                where: is_nil(wam.scheduled_deletion),
                select: %{trigger_id: twam.trigger_id, auth_method: wam}
              )
              |> Lightning.Repo.all()
              |> Enum.group_by(
                &Ecto.UUID.cast!(&1.trigger_id),
                & &1.auth_method
              )

            workflow = %Workflow{
              id: workflow_id,
              project_id: project.id,
              name: snapshot.name,
              lock_version: snapshot.lock_version,
              deleted_at: nil,
              jobs: Enum.map(snapshot.jobs, &Map.from_struct/1),
              edges: Enum.map(snapshot.edges, &Map.from_struct/1),
              triggers:
                Enum.map(snapshot.triggers, fn trigger ->
                  auth_methods = Map.get(trigger_auth_methods, trigger.id, [])

                  trigger
                  |> Map.from_struct()
                  |> Map.put(:has_auth_method, length(auth_methods) > 0)
                end)
            }

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

      _ ->
        {:error, "invalid version format"}
    end
  end

  defp load_workflow("edit", workflow_id, project, user, _version) do
    # IMPORTANT: Preload associations needed for Y.Doc initialization
    # When no persisted Y.Doc state exists, the workflow is serialized to Y.Doc
    # and needs jobs, edges, and triggers loaded to avoid empty workflow state
    case Lightning.Workflows.get_workflow(workflow_id,
           include: [
             :jobs,
             :edges,
             triggers:
               from(t in Lightning.Workflows.Trigger,
                 preload: [
                   webhook_auth_methods:
                     ^from(wam in Lightning.Workflows.WebhookAuthMethod,
                       where: is_nil(wam.scheduled_deletion),
                       order_by: wam.name
                     )
                 ]
               )
           ]
         ) do
      nil ->
        {:error, "workflow not found"}

      workflow ->
        if workflow.project_id != project.id do
          {:error, "workflow does not belong to specified project"}
        else
          case Permissions.can(
                 :workflows,
                 :access_read,
                 user,
                 project
               ) do
            :ok ->
              workflow_with_auth_flags = %{
                workflow
                | triggers:
                    Enum.map(workflow.triggers, fn trigger ->
                      %{
                        trigger
                        | has_auth_method:
                            length(trigger.webhook_auth_methods || []) > 0
                      }
                    end)
              }

              {:ok, workflow_with_auth_flags}

            {:error, :unauthorized} ->
              {:error, "unauthorized"}
          end
        end
    end
  end

  defp load_workflow("new", workflow_id, project, user, _version) do
    case Permissions.can(
           :project_users,
           :create_workflow,
           user,
           project
         ) do
      :ok ->
        workflow = %Lightning.Workflows.Workflow{
          id: workflow_id,
          project_id: project.id,
          name: "Untitled workflow",
          lock_version: nil,
          jobs: [],
          edges: [],
          triggers: []
        }

        {:ok, workflow}

      {:error, :unauthorized} ->
        {:error, "unauthorized"}
    end
  end

  defp load_workflow(action, _workflow_id, _project, _user, _version) do
    {:error, "invalid action '#{action}', must be 'new' or 'edit'"}
  end

  defp get_workflow_run_history(workflow_id, includes_run_id) do
    Lightning.WorkOrders.get_workorders_with_runs(workflow_id, includes_run_id)
    |> Enum.map(fn worder ->
      %{
        id: worder.id,
        state: worder.state,
        last_activity: worder.last_activity,
        version: worder.snapshot.lock_version,
        runs:
          Enum.map(worder.runs, fn run ->
            %{
              id: run.id,
              state: run.state,
              error_type: run.error_type,
              started_at: run.started_at,
              finished_at: run.finished_at
            }
          end)
      }
    end)
  end

  defp format_work_order_for_history(wo) do
    # Preload if needed
    wo = Repo.preload(wo, [:snapshot, :runs])

    %{
      id: wo.id,
      state: wo.state,
      last_activity: wo.last_activity,
      version: wo.snapshot.lock_version,
      runs: Enum.map(wo.runs, &format_run_for_history/1)
    }
  end

  defp format_run_for_history(run) do
    %{
      id: run.id,
      state: run.state,
      error_type: run.error_type,
      started_at: run.started_at,
      finished_at: run.finished_at
    }
  end

  defp format_run_steps_for_client(run) do
    steps =
      run.steps
      |> Enum.map(fn step ->
        %{
          id: step.id,
          job_id: step.job_id,
          exit_reason: step.exit_reason,
          error_type: step.error_type,
          started_at: step.started_at,
          finished_at: step.finished_at,
          input_dataclip_id: step.input_dataclip_id
        }
      end)

    %{
      run_id: run.id,
      steps: steps,
      metadata: %{
        starting_job_id: run.starting_job_id,
        starting_trigger_id: run.starting_trigger_id,
        inserted_at: run.inserted_at,
        created_by_id: run.created_by_id,
        created_by_email: run.created_by && run.created_by.email
      }
    }
  end
end
