defmodule LightningWeb.WorkflowChannel do
  @moduledoc """
  Phoenix Channel for binary Yjs collaboration messages.
  """
  use LightningWeb, :channel

  import Ecto.Query, only: [from: 2]

  alias Lightning.Collaborate
  alias Lightning.Collaboration.Session
  alias Lightning.Collaboration.Utils
  alias Lightning.Collaboration.WorkflowReconciler
  alias Lightning.Collaboration.WorkflowResolver
  alias Lightning.Policies.Permissions
  alias Lightning.Policies.ProjectUsers
  alias Lightning.Projects
  alias Lightning.Projects.Environment
  alias Lightning.Projects.Events.ProjectDeletionScheduled
  alias Lightning.Projects.Events.ProjectUserAdded
  alias Lightning.Projects.Events.ProjectUserRemoved
  alias Lightning.Projects.Events.ProjectUserRoleChanged
  alias Lightning.Projects.Events.SupportAccessUpdated
  alias Lightning.Projects.Events.WorkflowDeleted
  alias Lightning.Projects.MergeProjects
  alias Lightning.Projects.ProjectLimiter
  alias Lightning.Projects.Sandboxes
  alias Lightning.Projects.Scope
  alias Lightning.Repo
  alias Lightning.VersionControl
  alias Lightning.VersionControl.VersionControlUsageLimiter
  alias Lightning.Workflows
  alias Lightning.Workflows.Snapshot
  alias Lightning.Workflows.WorkflowRelease
  alias Lightning.Workflows.WorkflowReleases
  alias Lightning.Workflows.WorkflowUsageLimiter
  alias Lightning.WorkOrders
  alias LightningWeb.Channels.WorkflowJSON

  require Logger

  @impl true
  def join(
        "workflow:collaborate:" <> rest = topic,
        %{"project_id" => project_id, "action" => action},
        socket
      ) do
    {workflow_id, view} = parse_room_topic(rest)

    with {:user, user} when not is_nil(user) <-
           {:user, socket.assigns[:current_user]},
         {:project, %_{} = project} <-
           {:project, Lightning.Projects.get_project(project_id)},
         {:subscribed, :ok} <-
           {:subscribed, Lightning.Projects.Events.subscribe(project.id)},
         {:workflow, {:ok, workflow, workflow_kind}} <-
           {:workflow, load_workflow(action, workflow_id, project, user, view)} do
      Logger.info("""
      Joining workflow collaboration:
        workflow_id: #{workflow_id}
        view: #{inspect(view)}
        room: #{topic}
        is_latest: #{view == :latest}
      """)

      {:ok, session_pid} =
        Collaborate.start(
          user: user,
          workflow: workflow,
          room_topic: topic,
          view_only?: view != :latest
        )

      project_user = Lightning.Projects.get_project_user(project, user)

      permissions = user_permissions(user, project_user, project)

      # Subscribe to work order events for this workflow's project
      WorkOrders.subscribe(project.id)

      Phoenix.PubSub.subscribe(
        Lightning.PubSub,
        "workflow:collaborate:#{workflow_id}"
      )

      Lightning.Adaptors.subscribe_to_updates()

      {:ok,
       assign(socket,
         workflow_id: workflow_id,
         collaboration_topic: topic,
         workflow: workflow,
         project: project,
         session_pid: session_pid,
         project_user: project_user,
         workflow_kind: workflow_kind,
         content_locked: content_locked?(workflow, project, user)
       )
       |> assign(permissions)}
    else
      {:user, nil} -> {:error, %{reason: "unauthorized"}}
      {:project, nil} -> {:error, %{reason: "project not found"}}
      {:subscribed, _error} -> {:error, %{reason: "unable to join"}}
      {:workflow, {:error, reason}} -> {:error, %{reason: reason}}
    end
  end

  def join("workflow:collaborate:" <> _workflow_id, _params, _socket) do
    {:error, %{reason: "invalid parameters. project_id and action are required"}}
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
  def handle_in("request_metadata", %{"job_id" => job_id}, socket) do
    async_task(socket, "request_metadata", fn ->
      case Lightning.Jobs.get_job_with_credential(
             job_id,
             socket.assigns.workflow_id
           ) do
        nil ->
          %{
            job_id: job_id,
            metadata: %{error: "job_not_found"}
          }

        job ->
          # The adaptor describes a real credential, so it has to be the body
          # this project would actually run with. A sandbox with no environment
          # reports the error the same way a missing job does, rather than
          # raising inside the task.
          metadata =
            with {:ok, environment} <-
                   Environment.fetch(socket.assigns.project),
                 {:ok, metadata} <-
                   Lightning.MetadataService.fetch(
                     job.adaptor,
                     job.credential,
                     environment
                   ) do
              metadata
            else
              {:error, %{type: error_type}} -> %{error: error_type}
              {:error, reason} -> %{error: to_string(reason)}
            end

          %{job_id: job_id, metadata: metadata}
      end
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
    async_task(socket, "get_context", fn -> build_session_context(socket) end)
  end

  @impl true
  def handle_in("get_limits", %{"action_type" => action_type}, socket) do
    project = socket.assigns.project

    async_task(socket, "get_limits", fn ->
      limit_result = check_action_limit(action_type, project.id)

      %{
        action_type: action_type,
        limit: render_limit_result(limit_result)
      }
    end)
  end

  @impl true
  def handle_in("yjs_sync", {:binary, chunk}, socket) do
    Logger.debug(fn ->
      """
      WorkflowChannel: handle_in, yjs_sync
        from=#{inspect(self())}
        chunk=#{inspect(Utils.decipher_message(chunk))}
      """
    end)

    if forward_yjs_message?(chunk, socket) do
      Session.start_sync(socket.assigns.session_pid, chunk)
    end

    {:noreply, socket}
  end

  def handle_in("yjs", {:binary, chunk}, socket) do
    Logger.debug(fn ->
      """
      WorkflowChannel: handle_in, yjs
        from=#{inspect(self())}
        chunk=#{inspect(Utils.decipher_message(chunk))}
      """
    end)

    if forward_yjs_message?(chunk, socket) do
      Session.send_yjs_message(socket.assigns.session_pid, chunk)
    end

    {:noreply, socket}
  end

  @impl true
  def handle_in(
        "request_history",
        %{"version_number" => version_number},
        socket
      )
      when not is_nil(version_number) do
    workflow =
      Workflows.get_workflow(socket.assigns.workflow_id) ||
        socket.assigns.workflow

    filter = history_filter(version_number)

    async_task(socket, "request_history", fn ->
      %{history: get_filtered_run_history(workflow.id, filter)}
    end)
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
  Saves the current Y.Doc state through the Session.

  The reply is deferred. `Session.save_workflow/2` may wait on the adaptor
  catalogue's first load, so the call runs off the channel process and
  the reply goes out with `Phoenix.Channel.reply/2` when it finishes.

  Success: `{:ok, %{saved_at: DateTime, lock_version: integer}}`
  Error: `{:error, %{errors: map, type: string}}`
  """
  @impl true
  def handle_in("save_workflow", _params, socket) do
    case authorize_content_edit(socket) do
      :ok ->
        session_pid = socket.assigns.session_pid
        user = socket.assigns.current_user

        defer_reply(socket, :save_workflow_reply, fn ->
          Session.save_workflow(session_pid, user)
        end)

      error ->
        {:reply, workflow_error_reply(error), socket}
    end
  end

  @impl true
  def handle_in("go_live", _params, socket) do
    transition_lifecycle_state(socket, :live)
  end

  @impl true
  def handle_in("switch_to_draft", _params, socket) do
    transition_lifecycle_state(socket, :draft)
  end

  @impl true
  def handle_in(
        "set_suppress_enable_trigger_warning",
        %{"suppress" => suppress},
        socket
      )
      when is_boolean(suppress) do
    {:ok, _user} =
      Lightning.Accounts.update_user_preference(
        socket.assigns.current_user,
        "suppress_enable_trigger_warning",
        suppress
      )

    {:reply, {:ok, %{}}, socket}
  end

  @impl true
  def handle_in("list_sandboxes", _params, socket) do
    project = socket.assigns.project
    user = socket.assigns.current_user

    case authorize_provision_sandbox(user, project) do
      :ok ->
        sandboxes =
          project.id
          |> Projects.list_active_sandboxes_for_editing(
            current_workflow_name(socket)
          )
          |> Enum.reject(fn {_sandbox, joinable_workflow_id} ->
            is_nil(joinable_workflow_id)
          end)
          |> Enum.map(&render_editable_sandbox/1)

        {:reply, {:ok, %{sandboxes: sandboxes}}, socket}

      error ->
        {:reply, workflow_error_reply(error), socket}
    end
  end

  @impl true
  def handle_in("edit_in_sandbox", params, socket) do
    parent = socket.assigns.project
    user = socket.assigns.current_user

    branch_from_name = current_workflow_name(socket)

    attrs =
      %{
        name: sandbox_name(params, branch_from_name, parent),
        env: "dev",
        color: LightningWeb.SandboxLive.Components.random_color()
      }
      |> put_starting_data(params)

    with :ok <- authorize_provision_sandbox(user, parent),
         :ok <- limit_new_sandbox(parent),
         :ok <- check_chosen_dataclip(parent, attrs),
         {:ok,
          %{
            sandbox: sandbox,
            workflow: cloned_workflow,
            starting_dataclip_id: starting_dataclip_id
          }} <-
           Projects.provision_editing_sandbox(
             parent,
             user,
             branch_from_name,
             attrs
           ) do
      {:reply,
       {:ok,
        %{
          project_id: sandbox.id,
          workflow_id: cloned_workflow.id,
          dataclip_id: starting_dataclip_id
        }}, socket}
    else
      error -> {:reply, workflow_error_reply(error), socket}
    end
  end

  @impl true
  def handle_in("request_promote_check", params, socket) do
    sandbox = socket.assigns.project
    user = socket.assigns.current_user

    workflow_name =
      case params do
        %{"workflow_name" => name} when is_binary(name) and name != "" -> name
        _ -> socket.assigns.workflow.name
      end

    async_task(socket, "request_promote_check", fn ->
      with %_{} = parent <- fetch_parent_project(sandbox),
           :ok <- authorize_merge_sandbox(user, parent) do
        %{
          diverged:
            MergeProjects.workflow_diverged?(sandbox, parent, workflow_name),
          parent_name: parent.name
        }
      else
        _ -> %{diverged: false, parent_name: nil}
      end
    end)
  end

  @impl true
  def handle_in("request_restore_check", %{"version_number" => number}, socket)
      when is_integer(number) do
    workflow = socket.assigns.workflow

    async_task(socket, "request_restore_check", fn ->
      with :ok <- authorize_edit_workflow(socket),
           %WorkflowRelease{snapshot: %_{} = snapshot} <-
             WorkflowReleases.get_by_version_number(workflow.id, number) do
        %{
          losing_triggers: render_losing_triggers(workflow, snapshot),
          returning_triggers: render_returning_triggers(workflow, snapshot),
          version_number: number
        }
      else
        _ ->
          %{losing_triggers: [], returning_triggers: [], version_number: number}
      end
    end)
  end

  @impl true
  def handle_in("restore_version", %{"version_number" => number}, socket)
      when is_integer(number) do
    workflow = socket.assigns.workflow
    user = socket.assigns.current_user

    with :ok <- authorize_edit_workflow(socket),
         %WorkflowRelease{snapshot: %_{}} = release <-
           WorkflowReleases.get_by_version_number(workflow.id, number),
         {:ok, restored} <- restore_or_conflict(workflow, release, user) do
      WorkflowReconciler.request_reconciliation(workflow.id)

      broadcast_workflow_saved(socket, restored)

      socket =
        if socket.assigns.workflow_kind == :version do
          socket
        else
          assign(socket, :workflow, restored)
        end

      push(socket, "session_context_updated", build_session_context(socket))

      {:reply, {:ok, %{lock_version: restored.lock_version}}, socket}
    else
      nil -> {:reply, workflow_error_reply({:error, :version_not_found}), socket}
      error -> {:reply, workflow_error_reply(error), socket}
    end
  end

  @impl true
  def handle_in("promote", _params, socket) do
    sandbox = socket.assigns.project
    workflow = socket.assigns.workflow
    user = socket.assigns.current_user

    with %_{} = parent <- fetch_parent_project(sandbox),
         :ok <- authorize_merge_sandbox(user, parent),
         {:ok, result} <- Projects.promote_workflow(workflow, user) do
      {:reply, {:ok, result}, socket}
    else
      nil -> {:reply, workflow_error_reply({:error, :not_a_sandbox}), socket}
      error -> {:reply, workflow_error_reply(error), socket}
    end
  end

  @impl true
  def handle_in("archive_sandbox", _params, socket) do
    sandbox = socket.assigns.project
    user = socket.assigns.current_user

    with %_{} = parent <- fetch_parent_project(sandbox),
         :ok <- authorize_delete_sandbox(user, sandbox),
         {:ok, _scheduled} <- Sandboxes.schedule_sandbox_deletion(sandbox, user) do
      {:reply, {:ok, %{parent_project_id: parent.id}}, socket}
    else
      nil -> {:reply, workflow_error_reply({:error, :not_a_sandbox}), socket}
      error -> {:reply, workflow_error_reply(error), socket}
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
    case authorize_content_edit(socket) do
      :ok ->
        session_pid = socket.assigns.session_pid
        user = socket.assigns.current_user
        project = socket.assigns.project

        defer_reply(socket, :save_and_sync_reply, fn ->
          with {:ok, workflow} <- Session.save_workflow(session_pid, user),
               repo_connection when not is_nil(repo_connection) <-
                 VersionControl.get_repo_connection_for_project(project.id),
               :ok <-
                 VersionControl.initiate_sync(repo_connection, commit_message) do
            {:ok, workflow, repo_connection}
          end
        end)

      error ->
        {:reply, workflow_error_reply(error), socket}
    end
  end

  @impl true
  def handle_in("reset_workflow", _params, socket) do
    session_pid = socket.assigns.session_pid
    user = socket.assigns.current_user

    with :ok <- authorize_content_edit(socket),
         {:ok, workflow} <- Session.reset_workflow(session_pid, user) do
      {:reply,
       {:ok,
        %{
          lock_version: workflow.lock_version,
          workflow_id: workflow.id
        }}, socket}
    else
      error -> {:reply, workflow_error_reply(error), socket}
    end
  end

  @impl true
  def handle_in("validate_workflow_name", %{"workflow" => params}, socket) do
    project = socket.assigns.project
    workflow_id = socket.assigns.workflow_id

    validated_params = ensure_unique_name(params, project, workflow_id)

    {:reply, {:ok, %{workflow: validated_params}}, socket}
  end

  @impl true
  def handle_in(
        "check_custom_path",
        %{"custom_path" => custom_path, "trigger_id" => trigger_id},
        socket
      ) do
    taken =
      Lightning.Workflows.custom_path_taken?(
        custom_path,
        socket.assigns.project.id,
        trigger_id
      )

    {:reply, {:ok, %{taken: taken}}, socket}
  end

  @impl true
  def handle_in("request_releases", _payload, socket) do
    workflow = socket.assigns.workflow
    workflow_kind = socket.assigns.workflow_kind

    async_task(socket, "request_releases", fn ->
      if workflow_kind == :new do
        %{releases: []}
      else
        releases =
          case Lightning.Workflows.WorkflowReleases.list_for_workflow(
                 workflow.id
               ) do
            [] ->
              []

            [latest | rest] ->
              [
                render_release(latest, true)
                | Enum.map(rest, &render_release(&1, false))
              ]
          end

        %{releases: releases}
      end
    end)
  end

  @impl true
  def handle_in("request_versions", _payload, socket) do
    workflow = socket.assigns.workflow
    workflow_kind = socket.assigns.workflow_kind

    async_task(socket, "request_versions", fn ->
      # short-circuit to an empty list rather than reloading a nil row.
      if workflow_kind == :new do
        %{versions: []}
      else
        latest_lock_version =
          Lightning.Workflows.get_workflow(workflow.id).lock_version

        versions =
          workflow
          |> Snapshot.get_all_for()
          |> Enum.map(fn snapshot ->
            %{
              lock_version: snapshot.lock_version,
              inserted_at: snapshot.inserted_at,
              is_latest: snapshot.lock_version == latest_lock_version
            }
          end)
          |> Enum.sort_by(fn version ->
            {if(version.is_latest, do: 0, else: 1), -version.lock_version}
          end)

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

    project_id = socket.assigns.project.id

    async_task(socket, "request_trigger_auth_methods", fn ->
      webhook_auth_methods_query =
        from(wam in Lightning.Workflows.WebhookAuthMethod,
          join: t in assoc(wam, :triggers),
          where: t.id == ^trigger_id,
          where: wam.project_id == ^project_id,
          where: is_nil(wam.scheduled_deletion),
          order_by: wam.name
        )

      webhook_auth_methods = Repo.all(webhook_auth_methods_query)

      %{
        trigger_id: trigger_id,
        webhook_auth_methods: render_webhook_auth_methods(webhook_auth_methods)
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

    with :ok <- authorize_content_edit(socket),
         :ok <- authorize_write_webhook_auth_method(socket),
         %Lightning.Workflows.Trigger{} = trigger <-
           get_trigger_for_workflow(trigger_id, socket.assigns.workflow_id),
         auth_methods <-
           fetch_auth_methods(auth_method_ids, socket.assigns.project),
         {:ok, updated_trigger} <-
           Lightning.WebhookAuthMethods.update_trigger_auth_methods(
             trigger,
             auth_methods,
             actor: socket.assigns.current_user
           ) do
      # Broadcast update to all collaborators in the room (including sender).
      # Echo the trigger's canonical id, not the client-supplied one, so every
      # client keys the update the same way.
      broadcast!(socket, "trigger_auth_methods_updated", %{
        trigger_id: updated_trigger.id,
        webhook_auth_methods:
          render_webhook_auth_methods(updated_trigger.webhook_auth_methods)
      })

      {:reply, {:ok, %{success: true}}, socket}
    else
      {:error, %{type: "unauthorized", message: message}} ->
        {:reply, {:error, %{reason: message}}, socket}

      # A trigger that isn't in this workflow (missing, in another workflow, or
      # a malformed id) all read as "trigger not found", so the reply never
      # reveals whether a trigger exists outside this workflow.
      nil ->
        {:reply, {:error, %{reason: "trigger not found"}}, socket}

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
      error -> {:reply, workflow_error_reply(error), socket}
    end
  end

  @impl true
  def handle_in("list_templates", _params, socket) do
    templates = Lightning.WorkflowTemplates.list_templates()
    rendered_templates = Enum.map(templates, &render_workflow_template/1)

    {:reply, {:ok, %{templates: rendered_templates}}, socket}
  end

  # Handles the start of an AI workflow apply operation.
  # When a user clicks "Apply" on an AI-generated workflow, this broadcasts
  # to all collaborators so they can disable their Apply buttons, preventing
  # concurrent applies that could cause duplicate nodes in Y.Doc.
  @impl true
  def handle_in("start_applying_workflow", %{"message_id" => message_id}, socket) do
    user = socket.assigns.current_user

    # Broadcast to ALL clients (including sender) so everyone sees the applying state
    broadcast!(socket, "workflow_applying", %{
      user_id: user.id,
      user_name: user.first_name || user.email,
      message_id: message_id
    })

    {:reply, {:ok, %{}}, socket}
  end

  # Handles the completion of an AI workflow apply operation.
  # Broadcasts to all collaborators that the apply is complete, allowing them
  # to re-enable their Apply buttons.
  @impl true
  def handle_in("done_applying_workflow", %{"message_id" => message_id}, socket) do
    # Broadcast to ALL clients (including sender) so everyone clears the applying state
    broadcast!(socket, "workflow_applied", %{
      message_id: message_id
    })

    {:reply, {:ok, %{}}, socket}
  end

  # Handles the start of an AI job code apply operation.
  # When a user clicks "Apply" on AI-generated job code, this broadcasts
  # to all collaborators so they can disable their Apply buttons, preventing
  # concurrent applies that could cause Y.Doc conflicts.
  @impl true
  def handle_in("start_applying_job_code", %{"message_id" => message_id}, socket) do
    user = socket.assigns.current_user

    # Broadcast to ALL clients (including sender) so everyone sees the applying state
    broadcast!(socket, "job_code_applying", %{
      user_id: user.id,
      user_name: user.first_name || user.email,
      message_id: message_id
    })

    {:reply, {:ok, %{}}, socket}
  end

  # Handles the completion of an AI job code apply operation.
  # Broadcasts to all collaborators that the apply is complete, allowing them
  # to re-enable their Apply buttons.
  @impl true
  def handle_in("done_applying_job_code", %{"message_id" => message_id}, socket) do
    # Broadcast to ALL clients (including sender) so everyone clears the applying state
    broadcast!(socket, "job_code_applied", %{
      message_id: message_id
    })

    {:reply, {:ok, %{}}, socket}
  end

  # A stale client tab may still send an event removed in a later deploy.
  # Replying with an error instead of raising FunctionClauseError keeps this
  # client's channel process and connection alive.
  @impl true
  def handle_in(event, _payload, socket) do
    warn_unhandled_message("handle_in", event)
    {:reply, {:error, %{reason: "unknown event: #{event}"}}, socket}
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
  def handle_info({:save_workflow_reply, ref, {:ok, workflow}}, socket) do
    # broadcast_from! skips the saving client, which already gets its
    # lock_version through the reply below; everyone else needs this to
    # update their latestSnapshotLockVersion in SessionContextStore.
    broadcast_from!(socket, "workflow_saved", %{
      latest_snapshot_lock_version: workflow.lock_version,
      workflow: workflow
    })

    reply(
      ref,
      {:ok,
       %{
         saved_at: workflow.updated_at,
         lock_version: workflow.lock_version,
         workflow: workflow
       }}
    )

    # The workflow now has a DB row, so this channel is no longer editing a
    # brand-new (:new) workflow. No client rejoin happens after a first save,
    # so we must self-promote the cached kind + struct here; otherwise
    # request_versions / get_context keep short-circuiting to empty for the
    # rest of this session (until a full page refresh re-joins as :existing).
    {:noreply, assign(socket, workflow: workflow, workflow_kind: :existing)}
  end

  @impl true
  def handle_info({:save_workflow_reply, ref, error}, socket) do
    reply(ref, workflow_error_reply(error))
    {:noreply, socket}
  end

  @impl true
  def handle_info(
        {:save_and_sync_reply, ref, {:ok, workflow, repo_connection}},
        socket
      ) do
    broadcast_from!(socket, "workflow_saved", %{
      latest_snapshot_lock_version: workflow.lock_version,
      workflow: workflow
    })

    reply(
      ref,
      {:ok,
       %{
         saved_at: workflow.updated_at,
         lock_version: workflow.lock_version,
         repo: repo_connection.repo,
         workflow: workflow
       }}
    )

    {:noreply, socket}
  end

  @impl true
  def handle_info({:save_and_sync_reply, ref, nil}, socket) do
    reply(
      ref,
      {:error,
       %{
         errors: %{base: ["No GitHub connection configured for this project"]},
         type: "github_sync_error"
       }}
    )

    {:noreply, socket}
  end

  @impl true
  def handle_info({:save_and_sync_reply, ref, {:error, reason}}, socket)
      when is_binary(reason) do
    reply(
      ref,
      {:error,
       %{
         errors: %{base: [reason]},
         type: "github_sync_error"
       }}
    )

    {:noreply, socket}
  end

  @impl true
  def handle_info({:save_and_sync_reply, ref, error}, socket) do
    reply(ref, workflow_error_reply(error))
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
  def handle_info(%{event: "adaptors_updated", payload: payload}, socket) do
    push(socket, "adaptors_updated", payload)
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
      version_numbers =
        WorkflowReleases.version_numbers_by_lock_version(wo.workflow_id)

      formatted_wo = format_work_order_for_history(wo, version_numbers)

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
      version_numbers =
        WorkflowReleases.version_numbers_by_lock_version(wo.workflow_id)

      formatted_wo = format_work_order_for_history(wo, version_numbers)

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
        version_numbers =
          WorkflowReleases.version_numbers_by_lock_version(workflow_id)

        formatted_run = format_run_for_history(run, version_numbers)

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
        version_numbers =
          WorkflowReleases.version_numbers_by_lock_version(workflow_id)

        formatted_run = format_run_for_history(run, version_numbers)

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

  # The project is wound down, so nobody may work in it and no later change can
  # make it writable again. `save_workflow` already refuses, but Yjs frames are
  # gated on `assigns.can_edit_workflow` — resolved at join and never lowered by
  # this event — so the shared document stays writable until the channel goes.
  # Ending it is the only thing that stops those mutations reaching every other
  # participant in the room.
  @impl true
  def handle_info(%ProjectDeletionScheduled{}, socket) do
    {:stop, :normal, socket}
  end

  @impl true
  def handle_info(
        %WorkflowDeleted{workflow_id: workflow_id},
        %{assigns: %{workflow_id: workflow_id}} = socket
      ) do
    {:stop, :normal, socket}
  end

  # We lost access entirely, so there is nothing left to re-authorise: drop the
  # channel.
  @impl true
  def handle_info(
        %ProjectUserRemoved{user_id: user_id},
        %{assigns: %{current_user: %{id: user_id}}} = socket
      ) do
    {:stop, :normal, socket}
  end

  # Support access is this session's only standing on the project, so losing it
  # leaves nothing to re-authorise. A member's channel is unaffected: their row
  # outranks support access, and turning support access on cannot reach a
  # support-access session that could not have joined without it.
  @impl true
  def handle_info(
        %SupportAccessUpdated{},
        %{assigns: %{current_user: %{support_user: true}, project_user: nil}} =
          socket
      ) do
    {:stop, :normal, socket}
  end

  # Being added can narrow permissions as much as a role change can: a support
  # user given a low role loses the access their support standing granted.
  @impl true
  def handle_info(
        %event{user_id: user_id},
        %{assigns: %{current_user: %{id: user_id} = user, project: project}} =
          socket
      )
      when event in [ProjectUserAdded, ProjectUserRoleChanged] do
    project_user = Lightning.Projects.get_project_user(project, user)

    permissions = user_permissions(user, project_user, project)

    socket =
      socket
      |> assign(:project_user, project_user)
      |> assign(permissions)

    push(socket, "session_context_updated", build_session_context(socket))

    {:noreply, socket}
  end

  @impl true
  def handle_info(%event{}, socket)
      when event in [
             ProjectUserAdded,
             ProjectUserRemoved,
             ProjectUserRoleChanged,
             SupportAccessUpdated,
             WorkflowDeleted
           ] do
    {:noreply, socket}
  end

  # A PubSub broadcast for an event type removed in a later deploy can still
  # arrive here. Logging instead of raising FunctionClauseError keeps this
  # client's channel process and connection alive.
  @impl true
  def handle_info(
        %Phoenix.Socket.Broadcast{event: "workflow_saved", payload: payload},
        socket
      ) do
    push(socket, "workflow_saved", payload)
    {:noreply, socket}
  end

  @impl true
  def handle_info(message, socket) do
    warn_unhandled_message("handle_info", unhandled_message_type(message))

    {:noreply, socket}
  end

  intercept ["workflow_saved"]

  @impl true
  def handle_out("workflow_saved", payload, socket) do
    push(socket, "workflow_saved", payload)

    {:noreply, refresh_lifecycle_from_broadcast(socket, payload)}
  end

  def handle_out(event, payload, socket) do
    push(socket, event, payload)
    {:noreply, socket}
  end

  defp refresh_lifecycle_from_broadcast(
         %{assigns: %{workflow_kind: :existing, workflow: %{state: was}}} =
           socket,
         %{workflow: %{state: now} = workflow}
       )
       when was != now do
    socket = refresh_lifecycle_lock(socket, workflow)
    push(socket, "session_context_updated", build_session_context(socket))

    push(socket, "lifecycle_changed", %{state: now})

    socket
  end

  defp refresh_lifecycle_from_broadcast(socket, _payload), do: socket

  # Unlinked on purpose. A GenServer.call timeout or dead target exits, and
  # a linked task would take the channel down. `catch :exit` turns it into
  # an error reply instead.
  defp async_task(socket, event, task_fn) do
    channel_pid = self()
    socket_ref = socket_ref(socket)

    Task.start(fn ->
      result =
        try do
          {:ok, task_fn.()}
        rescue
          error ->
            Logger.error("Failed to handle #{event}: #{inspect(error)}")
            {:error, %{reason: "failed to handle #{event}"}}
        catch
          :exit, reason ->
            Logger.error("Failed to handle #{event}: #{inspect(reason)}")
            {:error, %{reason: "failed to handle #{event}"}}
        end

      send(channel_pid, {:async_reply, socket_ref, event, result})
    end)

    {:noreply, socket}
  end

  # As `async_task/3`, but the reply is post-processed by the `handle_info/2`
  # clause for `tag`.
  defp defer_reply(socket, tag, task_fn) do
    channel_pid = self()
    ref = socket_ref(socket)

    Task.start(fn ->
      result =
        try do
          task_fn.()
        rescue
          error ->
            Logger.error("Failed to handle #{tag}: #{inspect(error)}")
            {:error, :internal_error}
        catch
          :exit, reason ->
            Logger.error("Failed to handle #{tag}: #{inspect(reason)}")
            {:error, :internal_error}
        end

      send(channel_pid, {tag, ref, result})
    end)

    {:noreply, socket}
  end

  # Only the event name goes to the log and Sentry. The full message or
  # payload may carry user or workflow data.
  defp warn_unhandled_message(kind, event) do
    Logger.warning("WorkflowChannel: unhandled #{kind} event: #{event}")

    Sentry.capture_message(
      "WorkflowChannel: unhandled #{kind} event: #{event}",
      level: :warning
    )
  end

  defp unhandled_message_type(%{event: event}), do: event
  defp unhandled_message_type(%struct{}), do: inspect(struct)
  defp unhandled_message_type(_msg), do: "unrecognised"

  defp handle_async_event("request_run_steps", socket_ref, reply) do
    unwrapped_reply = unwrap_run_steps_reply(reply)
    reply(socket_ref, unwrapped_reply)
  end

  defp handle_async_event(event, socket_ref, reply)
       when event in [
              "request_credentials",
              "request_metadata",
              "request_current_user",
              "get_context",
              "request_history",
              "request_releases",
              "request_versions",
              "request_promote_check",
              "request_restore_check",
              "request_trigger_auth_methods",
              "get_limits"
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

  defp build_session_context(socket) do
    user = socket.assigns[:current_user]
    workflow = socket.assigns.workflow
    project = socket.assigns.project
    workflow_kind = socket.assigns.workflow_kind

    permissions =
      Map.take(socket.assigns, [
        :can_edit_workflow,
        :can_run_workflow,
        :can_write_webhook_auth_method,
        :can_provision_sandbox,
        :can_archive_sandbox
      ])

    latest_row =
      workflow_kind != :new &&
        Lightning.Workflows.get_workflow(
          workflow.id,
          if(workflow_kind == :existing,
            do: [include: [:edges, :jobs, :triggers]],
            else: []
          )
        )

    latest_lock_version =
      case latest_row do
        %Lightning.Workflows.Workflow{lock_version: lock_version} ->
          lock_version

        _ ->
          if workflow_kind == :new, do: nil, else: workflow.lock_version
      end

    fresh_workflow =
      case {workflow_kind, latest_row} do
        {:existing, %Lightning.Workflows.Workflow{} = row} ->
          row

        {:version, %Lightning.Workflows.Workflow{state: state}} ->
          %{workflow | state: state}

        _ ->
          workflow
      end

    project_repo_connection =
      VersionControl.get_repo_connection_for_project(project.id)

    webhook_auth_methods = Lightning.WebhookAuthMethods.list_for_project(project)

    workflow_template =
      Lightning.WorkflowTemplates.get_template_by_workflow_id(workflow.id)

    %{
      user: render_user_context(user),
      project: render_project_context(project),
      config: render_config_context(),
      permissions: permissions,
      content_locked: socket.assigns.content_locked,
      latest_snapshot_lock_version: latest_lock_version,
      latest_snapshot_id: Snapshot.current_id_for(workflow.id),
      project_repo_connection: render_repo_connection(project_repo_connection),
      webhook_auth_methods: render_webhook_auth_methods(webhook_auth_methods),
      workflow_template: render_workflow_template(workflow_template),
      suppress_enable_trigger_warning:
        Lightning.Accounts.get_preference(
          user,
          "suppress_enable_trigger_warning"
        ) == true,
      experimental_features_enabled:
        Lightning.Accounts.experimental_features_enabled?(user),
      limits: render_limits(project.id),
      workflow: fresh_workflow
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
      name: project.name,
      concurrency: project.concurrency,
      is_sandbox: not is_nil(project.parent_id)
    }
  end

  defp render_config_context do
    %{
      require_email_verification:
        Lightning.Config.check_flag?(:require_email_verification),
      max_dataclip_size_bytes: Lightning.Config.max_dataclip_size_bytes()
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

  defp restore_or_conflict(workflow, release, user) do
    Workflows.restore_version(workflow, release, user)
  rescue
    Ecto.StaleEntryError -> {:error, :workflow_moved_on}
  end

  defp render_losing_triggers(workflow, snapshot) do
    kept = MapSet.new(snapshot.triggers, & &1.id)

    workflow
    |> Lightning.Repo.preload(:triggers, force: true)
    |> Map.fetch!(:triggers)
    |> Enum.reject(&MapSet.member?(kept, &1.id))
    |> Enum.map(
      &%{
        id: &1.id,
        type: &1.type,
        custom_path: &1.custom_path,
        enabled: &1.enabled
      }
    )
  end

  defp render_returning_triggers(workflow, snapshot) do
    live =
      workflow
      |> Lightning.Repo.preload(:triggers, force: true)
      |> Map.fetch!(:triggers)
      |> MapSet.new(& &1.id)

    snapshot.triggers
    |> Enum.reject(&MapSet.member?(live, &1.id))
    |> Enum.map(&%{id: &1.id, type: &1.type, custom_path: &1.custom_path})
  end

  defp render_release(release, is_latest) do
    %{
      version_number: release.version_number,
      kind: release.kind,
      inserted_at: release.inserted_at,
      published_by: render_release_publisher(release.published_by),
      source_project: render_release_source_project(release.source_project),
      lock_version: release.snapshot && release.snapshot.lock_version,
      snapshot_id: release.snapshot_id,
      restored_from_version_number: release.restored_from_version_number,
      is_latest: is_latest
    }
  end

  defp render_release_publisher(nil), do: nil
  defp render_release_publisher(%_{} = user), do: collaborator_name(user)

  defp render_release_source_project(nil), do: nil
  defp render_release_source_project(%_{name: name}), do: name

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

  defp content_locked?(workflow, project, user) do
    Lightning.Accounts.experimental_features_enabled?(user) and
      not Lightning.Workflows.editable_state?(workflow, project)
  end

  # Without a membership row the policy needs the project itself to weigh up
  # support access. Resolve the standing once and decide all three questions
  # against it — three `Permissions.can?/4` calls would resolve three Scopes for
  # one unchanging answer.
  defp user_permissions(user, project_user, project) do
    case Scope.fetch(user, project_user || project) do
      {:ok, scope} ->
        %{
          can_edit_workflow: ProjectUsers.permitted?(:edit_workflow, scope),
          can_run_workflow: ProjectUsers.permitted?(:run_workflow, scope),
          can_write_webhook_auth_method:
            ProjectUsers.permitted?(:write_webhook_auth_method, scope),
          can_provision_sandbox:
            Permissions.can?(:sandboxes, :provision_sandbox, user, project),
          can_archive_sandbox:
            not is_nil(project.parent_id) and
              Permissions.can?(:sandboxes, :delete_sandbox, user, project)
        }

      # No such project, or one scheduled for deletion.
      {:error, _reason} ->
        %{
          can_edit_workflow: false,
          can_run_workflow: false,
          can_write_webhook_auth_method: false,
          can_provision_sandbox: false,
          can_archive_sandbox: false
        }
    end
  end

  defp publish_template(socket, params) do
    workflow = socket.assigns.workflow
    template_params = Map.put(params, "workflow_id", workflow.id)

    case Lightning.WorkflowTemplates.create_template(template_params) do
      {:ok, template} -> {:ok, template}
      {:error, changeset} -> {:error, changeset}
    end
  end

  # Returns the bare reply payload so both `handle_in` and the deferred
  # `handle_info` clauses can use it.
  defp workflow_error_reply({:error, %{type: type, message: message}}) do
    {:error,
     %{
       errors: %{base: [message]},
       type: type
     }}
  end

  defp workflow_error_reply({:error, :starting_dataclip_invalid_json}) do
    starting_dataclip_error("The input you reviewed is not valid JSON.")
  end

  defp workflow_error_reply({:error, :starting_dataclip_not_an_object}) do
    starting_dataclip_error("The input you reviewed must be a JSON object.")
  end

  defp workflow_error_reply({:error, :starting_dataclip_too_large}) do
    starting_dataclip_error(
      "The input you reviewed is too large to copy into a sandbox."
    )
  end

  defp workflow_error_reply({:error, :invalid_starting_dataclip}) do
    starting_dataclip_error("The input you reviewed could not be read.")
  end

  defp workflow_error_reply({:error, :starting_dataclip_not_found}) do
    starting_dataclip_error(
      "That saved input is no longer available in this project."
    )
  end

  defp workflow_error_reply({:error, :read_only_view}) do
    {:error,
     %{
       errors: %{
         base: [
           "You are reading an older version of this workflow. " <>
             "Go to the latest version to make changes."
         ]
       },
       type: "read_only_view"
     }}
  end

  defp workflow_error_reply({:error, :workflow_deleted}) do
    {:error,
     %{
       errors: %{base: ["This workflow has been deleted"]},
       type: "workflow_deleted"
     }}
  end

  defp workflow_error_reply({:error, :deserialization_failed}) do
    {:error,
     %{
       errors: %{base: ["Failed to extract workflow data from editor"]},
       type: "deserialization_error"
     }}
  end

  defp workflow_error_reply({:error, :internal_error}) do
    {:error,
     %{
       errors: %{base: ["An internal error occurred"]},
       type: "internal_error"
     }}
  end

  defp workflow_error_reply({:error, :nesting_too_deep}) do
    {:error,
     %{
       errors: %{
         base: ["This project is nested too deeply to create another sandbox"]
       },
       type: "nesting_too_deep"
     }}
  end

  defp workflow_error_reply({:error, :merge_failed}) do
    {:error,
     %{
       errors: %{base: ["Could not promote this workflow. Please try again."]},
       type: "merge_error"
     }}
  end

  defp workflow_error_reply({:error, :not_a_sandbox}) do
    {:error,
     %{
       errors: %{
         base: ["This workflow is not in a sandbox and can't be promoted."]
       },
       type: "invalid_state"
     }}
  end

  defp workflow_error_reply({:error, :snapshot_failed}) do
    {:error,
     %{
       errors: %{base: ["An internal error occurred"]},
       type: "internal_error"
     }}
  end

  defp workflow_error_reply({:error, :adaptor_catalogue_unavailable}) do
    {:error,
     %{
       errors: %{
         base: ["The adaptor catalogue is still loading. Try again shortly."]
       },
       type: "adaptor_catalogue_unavailable"
     }}
  end

  defp workflow_error_reply({:error, :workflow_moved_on}) do
    {:error,
     %{
       errors: %{
         base: ["Someone else saved this workflow. Try the restore again."]
       },
       type: "workflow_moved_on"
     }}
  end

  defp workflow_error_reply({:error, :version_not_found}) do
    {:error,
     %{
       errors: %{base: ["That version no longer exists"]},
       type: "version_not_found"
     }}
  end

  defp workflow_error_reply({:error, %Lightning.Extensions.Message{text: text}}) do
    {:error,
     %{
       errors: %{base: [text]},
       type: "limit_error"
     }}
  end

  defp workflow_error_reply({:error, %Ecto.Changeset{} = changeset}) do
    {:error,
     %{
       errors: format_changeset_errors(changeset),
       type: determine_error_type(changeset)
     }}
  end

  # Last resort: never let an unexpected error reason crash the channel and drop
  # the user's socket. Log it and reply with a generic internal error.
  defp workflow_error_reply(error) do
    Logger.warning("Unhandled workflow channel error: #{inspect(error)}")

    {:error,
     %{
       errors: %{base: ["An internal error occurred"]},
       type: "internal_error"
     }}
  end

  defp starting_dataclip_error(message) do
    {:error, %{errors: %{base: [message]}, type: "validation_error"}}
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

  # Yjs frame types that only read the shared document: the initial sync
  # handshake and presence/cursor updates. Any other frame type carries a
  # document update.
  @read_only_frame_types [:sync_step1, :awareness, :query_awareness]

  defp forward_yjs_message?(_chunk, %{
         assigns: %{
           can_edit_workflow: true,
           content_locked: false,
           workflow_kind: kind
         }
       })
       when kind != :version do
    true
  end

  defp forward_yjs_message?(chunk, socket) do
    case Utils.message_type(chunk) do
      type when type in @read_only_frame_types ->
        true

      type ->
        Logger.debug(fn ->
          "WorkflowChannel: dropped #{inspect(type)} from user " <>
            "#{socket.assigns.current_user.id} without edit permission " <>
            "on workflow #{socket.assigns.workflow_id}"
        end)

        false
    end
  end

  # Authorizes edit operations on the workflow by checking current user permissions.
  #
  # This function refetches the project_user to get the latest role, ensuring
  # that permission changes made during an active session are enforced.
  #
  # Returns :ok if authorized, {:error, %{type: string, message: string}} if not.
  defp apply_lifecycle_state(
         %{assigns: %{workflow_kind: :version}} = socket,
         target
       ) do
    %{current_user: user, workflow_id: workflow_id} = socket.assigns

    case Workflows.get_workflow(workflow_id) do
      nil ->
        {:error, :workflow_deleted}

      workflow ->
        workflow = Lightning.Repo.preload(workflow, :triggers)

        target
        |> case do
          :live -> go_live_within_limits(workflow, user)
          :draft -> Workflows.switch_to_draft(workflow, user)
        end
        |> case do
          {:ok, updated} ->
            {:ok, Repo.preload(updated, [:jobs, :edges, :triggers], force: true)}

          error ->
            error
        end
    end
  end

  defp apply_lifecycle_state(socket, target) do
    Session.set_workflow_state(
      socket.assigns.session_pid,
      socket.assigns.current_user,
      target
    )
  end

  defp go_live_within_limits(workflow, user) do
    activating? =
      Enum.any?(workflow.triggers, fn trigger -> !trigger.enabled end)

    case WorkflowUsageLimiter.limit_workflow_activation(
           activating?,
           workflow.project_id
         ) do
      :ok ->
        Workflows.go_live(workflow, user)

      {:error, _reason, %Lightning.Extensions.Message{} = message} ->
        {:error, message}

      other ->
        Logger.warning(
          "Unexpected usage limiter reply on go_live: #{inspect(other)}"
        )

        {:error, :internal_error}
    end
  end

  defp transition_lifecycle_state(socket, target_state) do
    with :ok <- authorize_edit_workflow(socket),
         {:ok, workflow} <- apply_lifecycle_state(socket, target_state) do
      broadcast_workflow_saved(socket, workflow)

      socket =
        if socket.assigns.workflow_kind == :version do
          assign(
            socket,
            :content_locked,
            content_locked?(
              workflow,
              socket.assigns.project,
              socket.assigns.current_user
            )
          )
        else
          refresh_lifecycle_lock(socket, workflow)
        end

      push(socket, "session_context_updated", build_session_context(socket))

      {:reply, {:ok, %{lock_version: workflow.lock_version, workflow: workflow}},
       socket}
    else
      error -> {:reply, workflow_error_reply(error), socket}
    end
  end

  defp broadcast_workflow_saved(socket, workflow) do
    LightningWeb.Endpoint.broadcast_from!(
      self(),
      "workflow:collaborate:#{socket.assigns.workflow_id}",
      "workflow_saved",
      %{
        latest_snapshot_lock_version: workflow.lock_version,
        workflow: workflow
      }
    )
  end

  defp refresh_lifecycle_lock(socket, workflow) do
    socket
    |> assign(:workflow, workflow)
    |> assign(
      :content_locked,
      content_locked?(
        workflow,
        socket.assigns.project,
        socket.assigns.current_user
      )
    )
  end

  defp authorize_content_edit(socket) do
    case authorize_edit_workflow(socket) do
      :ok -> ensure_editable_state(socket)
      error -> error
    end
  end

  defp ensure_editable_state(socket) do
    if content_locked?(
         current_workflow(socket),
         socket.assigns.project,
         socket.assigns.current_user
       ) do
      {:error,
       %{
         type: "unauthorized",
         message:
           "This workflow is live. Switch it to draft or edit it in a sandbox to make changes."
       }}
    else
      :ok
    end
  end

  defp current_workflow(socket) do
    case socket.assigns.workflow_kind do
      :new ->
        socket.assigns.workflow

      _ ->
        Workflows.get_workflow(socket.assigns.workflow.id) ||
          socket.assigns.workflow
    end
  end

  defp authorize_edit_workflow(socket) do
    authorize_project_user_action(
      socket,
      :edit_workflow,
      "You don't have permission to edit this workflow"
    )
  end

  defp authorize_write_webhook_auth_method(socket) do
    authorize_project_user_action(
      socket,
      :write_webhook_auth_method,
      "You don't have permission to manage webhook authentication"
    )
  end

  defp authorize_project_user_action(socket, action, unauthorized_message) do
    %{current_user: user, project: project} = socket.assigns
    project_user = Lightning.Projects.get_project_user(project, user)

    case Permissions.can(:project_users, action, user, project_user || project) do
      :ok ->
        :ok

      {:error, :unauthorized} ->
        {:error, %{type: "unauthorized", message: unauthorized_message}}
    end
  end

  defp authorize_provision_sandbox(user, parent) do
    if Permissions.can?(:sandboxes, :provision_sandbox, user, parent) do
      :ok
    else
      {:error,
       %{
         type: "unauthorized",
         message: "You don't have permission to create a sandbox here"
       }}
    end
  end

  defp authorize_merge_sandbox(user, parent) do
    if Permissions.can?(:sandboxes, :merge_sandbox, user, parent) do
      :ok
    else
      {:error,
       %{
         type: "unauthorized",
         message: "You don't have permission to promote this workflow"
       }}
    end
  end

  defp authorize_delete_sandbox(user, sandbox) do
    if Permissions.can?(:sandboxes, :delete_sandbox, user, sandbox) do
      :ok
    else
      {:error,
       %{
         type: "unauthorized",
         message: "You don't have permission to archive this sandbox"
       }}
    end
  end

  defp fetch_parent_project(%{parent_id: nil}), do: nil

  defp fetch_parent_project(%{parent_id: parent_id}),
    do: Projects.get_project(parent_id)

  defp limit_new_sandbox(parent) do
    case ProjectLimiter.limit_new_sandbox(parent.id) do
      :ok -> :ok
      {:error, _reason, message} -> {:error, message}
    end
  end

  defp check_chosen_dataclip(parent, %{dataclip_ids: ids}) do
    if Sandboxes.copyable_dataclips?(parent, ids),
      do: :ok,
      else: {:error, :starting_dataclip_not_found}
  end

  defp check_chosen_dataclip(_parent, _attrs), do: :ok

  defp put_starting_data(attrs, params) do
    case params do
      %{"starting_dataclip" => starting} ->
        Map.put(attrs, :starting_dataclip, starting)

      %{"dataclip_id" => dataclip_id} ->
        Map.put(attrs, :dataclip_ids, [dataclip_id])

      _ ->
        attrs
    end
  end

  defp sandbox_name(params, workflow_name, parent) do
    raw =
      case params do
        %{"name" => name} when is_binary(name) and name != "" -> name
        _ -> default_sandbox_name(workflow_name, parent)
      end

    Lightning.Helpers.url_safe_name(raw)
  end

  defp current_workflow_name(socket) do
    case Workflows.get_workflow(socket.assigns.workflow_id) do
      nil -> socket.assigns.workflow.name
      workflow -> workflow.name
    end
  end

  defp default_sandbox_name(workflow_name, parent) do
    base = workflow_name || parent.name || "sandbox"
    "#{base}-sandbox"
  end

  defp render_editable_sandbox({sandbox, joinable_workflow_id}) do
    %{
      id: sandbox.id,
      name: sandbox.name,
      color: sandbox.color,
      inserted_at: sandbox.inserted_at,
      updated_at: sandbox.updated_at,
      owner: render_owner(sandbox.project_users),
      workflow_id: joinable_workflow_id
    }
  end

  defp render_owner(project_users) do
    case Enum.find(project_users, &(&1.role == :owner)) do
      %{user: user} ->
        %{
          id: user.id,
          name: collaborator_name(user),
          email: user.email
        }

      nil ->
        nil
    end
  end

  defp collaborator_name(user) do
    [user.first_name, user.last_name]
    |> Enum.reject(&(is_nil(&1) or &1 == ""))
    |> Enum.join(" ")
    |> case do
      "" -> user.email
      name -> name
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

  defp ensure_unique_name(params, project, workflow_id) do
    Map.put(
      params,
      "name",
      Lightning.Workflows.unique_workflow_name(params["name"], project.id,
        exclude_workflow_id: workflow_id
      )
    )
  end

  # Loads a trigger only if it belongs to the given workflow, so existence and
  # ownership are one lookup. A missing, cross-workflow, or malformed id all
  # return nil (and a non-UUID never raises).
  defp get_trigger_for_workflow(trigger_id, workflow_id) do
    if match?({:ok, _}, Ecto.UUID.cast(trigger_id)) do
      Lightning.Repo.get_by(Lightning.Workflows.Trigger,
        id: trigger_id,
        workflow_id: workflow_id
      )
    end
  end

  defp fetch_auth_methods(ids, project) when is_list(ids) do
    Lightning.WebhookAuthMethods.list_for_project(project)
    |> Enum.filter(fn method -> method.id in ids end)
  end

  defp fetch_auth_methods(_ids, _project), do: []

  defp parse_room_topic(rest) do
    case String.split(rest, ":", parts: 2) do
      [workflow_id, "release" <> version] -> {workflow_id, {:release, version}}
      [workflow_id, "v" <> version] -> {workflow_id, {:version, version}}
      [workflow_id, "run:" <> run_id] -> {workflow_id, {:as_executed, run_id}}
      [workflow_id] -> {workflow_id, :latest}
      [workflow_id, suffix] -> {workflow_id, {:unknown, suffix}}
    end
  end

  defp load_workflow("edit", workflow_id, project, user, {:release, version}) do
    Logger.info("Loading workflow release version: #{version}")

    case Integer.parse(version) do
      {version_number, ""} ->
        resolve_release(workflow_id, version_number, version, project, user)

      _ ->
        {:error, "invalid version format"}
    end
  end

  defp load_workflow("edit", workflow_id, project, user, {:version, version}) do
    Logger.info("Loading workflow snapshot version: #{version}")

    case Integer.parse(version) do
      {lock_version, ""} ->
        resolve_snapshot(workflow_id, lock_version, version, project, user)

      _ ->
        {:error, "invalid version format"}
    end
  end

  defp load_workflow(
         "edit",
         workflow_id,
         project,
         user,
         {:as_executed, run_id}
       ) do
    resolve_as_executed(workflow_id, run_id, project, user)
  end

  defp load_workflow("edit", workflow_id, project, user, :latest) do
    with :ok <- Permissions.can(:workflows, :access_read, user, project),
         {:ok, workflow, kind} <-
           WorkflowResolver.resolve(workflow_id, :edit, project: project) do
      {:ok, workflow, kind}
    else
      {:error, :unauthorized} ->
        {:error, "unauthorized"}

      {:error, reason} when reason in [:workflow_not_found, :wrong_project] ->
        {:error, "workflow not found"}
    end
  end

  # New workflow. Auth before resolve, so an unauthorised create never resolves.
  #
  # The resolver reconciles by id, so a "new" join for an id owned by another
  # project returns {:error, :wrong_project}, mapped to the same client-facing
  # string as the "edit" path.
  defp load_workflow(_action, _workflow_id, _project, _user, {:unknown, suffix}) do
    {:error, "invalid room suffix '#{suffix}'"}
  end

  defp load_workflow("new", _workflow_id, _project, _user, view)
       when view != :latest do
    {:error, "invalid parameters. a new workflow has no version to pin"}
  end

  defp load_workflow("new", workflow_id, project, user, _view) do
    case Permissions.can(:project_users, :create_workflow, user, project) do
      :ok ->
        case WorkflowResolver.resolve(workflow_id, :new, project: project) do
          {:ok, workflow, kind} ->
            {:ok, workflow, kind}

          {:error, :wrong_project} ->
            {:error, "workflow not found"}
        end

      {:error, :unauthorized} ->
        {:error, "unauthorized"}
    end
  end

  defp load_workflow(action, _workflow_id, _project, _user, _view) do
    {:error, "invalid action '#{action}', must be 'new' or 'edit'"}
  end

  defp resolve_release(workflow_id, version_number, version, project, user) do
    with :ok <- Permissions.can(:workflows, :access_read, user, project),
         %Workflows.Workflow{} <-
           Workflows.get_workflow_for_project(project, workflow_id) do
      resolve_released_snapshot(workflow_id, version_number, version, project)
    else
      {:error, :unauthorized} -> {:error, "unauthorized"}
      _ -> {:error, "workflow not found"}
    end
  end

  defp resolve_snapshot(workflow_id, lock_version, version, project, user) do
    with :ok <- Permissions.can(:workflows, :access_read, user, project),
         {:ok, workflow, kind} <-
           WorkflowResolver.resolve(workflow_id, :edit,
             version: lock_version,
             project: project
           ) do
      {:ok, workflow, kind}
    else
      {:error, :unauthorized} ->
        {:error, "unauthorized"}

      {:error, :snapshot_not_found} ->
        {:error, "snapshot version #{version} not found"}

      {:error, reason} when reason in [:wrong_project, :workflow_not_found] ->
        {:error, "workflow not found"}
    end
  end

  defp resolve_released_snapshot(workflow_id, version_number, version, project) do
    with %WorkflowRelease{snapshot: %{lock_version: lock_version}} <-
           WorkflowReleases.get_by_version_number(workflow_id, version_number),
         {:ok, workflow, kind} <-
           WorkflowResolver.resolve(workflow_id, :edit,
             version: lock_version,
             project: project
           ) do
      {:ok, workflow, kind}
    else
      _ -> {:error, "snapshot version #{version} not found"}
    end
  end

  defp resolve_as_executed(workflow_id, run_id, project, user) do
    with :ok <- Permissions.can(:workflows, :access_read, user, project),
         {:ok, run_id} <- cast_run_id(run_id),
         lock_version when is_integer(lock_version) <-
           run_snapshot_lock_version(workflow_id, run_id),
         {:ok, workflow, kind} <-
           WorkflowResolver.resolve(workflow_id, :edit,
             version: lock_version,
             project: project
           ) do
      {:ok, workflow, kind}
    else
      {:error, :unauthorized} -> {:error, "unauthorized"}
      {:error, :snapshot_not_found} -> {:error, "run snapshot not found"}
      _ -> {:error, "run not found"}
    end
  end

  defp cast_run_id(run_id) do
    case Ecto.UUID.cast(run_id) do
      {:ok, run_id} -> {:ok, run_id}
      :error -> :error
    end
  end

  defp run_snapshot_lock_version(workflow_id, run_id) do
    from(r in Lightning.Run,
      join: s in assoc(r, :snapshot),
      where: r.id == ^run_id and s.workflow_id == ^workflow_id,
      select: s.lock_version
    )
    |> Repo.one()
  end

  defp history_filter(v) when v in ["draft", "unversioned"], do: :draft
  defp history_filter(v) when is_integer(v), do: {:release, v}

  defp history_filter(v) when is_binary(v) do
    case Integer.parse(v) do
      {n, ""} -> {:release, n}
      _ -> :draft
    end
  end

  defp get_filtered_run_history(workflow_id, {:release, version_number}) do
    version_numbers =
      WorkflowReleases.version_numbers_by_lock_version(workflow_id)

    workflow_id
    |> WorkOrders.get_workorders_for_version(version_number)
    |> Enum.map(&format_work_order_for_history(&1, version_numbers))
  end

  defp get_filtered_run_history(workflow_id, :draft) do
    version_numbers =
      WorkflowReleases.version_numbers_by_lock_version(workflow_id)

    workflow_id
    |> WorkOrders.get_workorders_unversioned()
    |> Enum.map(&format_work_order_for_history(&1, version_numbers))
  end

  defp get_workflow_run_history(workflow_id, includes_run_id) do
    version_numbers =
      WorkflowReleases.version_numbers_by_lock_version(workflow_id)

    workflow_id
    |> Lightning.WorkOrders.get_workorders_with_runs(includes_run_id)
    |> Enum.map(&format_work_order_for_history(&1, version_numbers))
  end

  defp format_work_order_for_history(wo, version_numbers) do
    # Preload if needed
    wo = Repo.preload(wo, runs: :snapshot)

    %{
      id: wo.id,
      state: wo.state,
      last_activity: wo.last_activity,
      runs: Enum.map(wo.runs, &format_run_for_history(&1, version_numbers))
    }
  end

  defp format_run_for_history(run, version_numbers) do
    # Preload snapshot if not already loaded
    run = Repo.preload(run, :snapshot)
    lock_version = run.snapshot && run.snapshot.lock_version

    %{
      id: run.id,
      state: run.state,
      error_type: run.error_type,
      started_at: run.started_at,
      finished_at: run.finished_at,
      version: lock_version,
      version_number: lock_version && Map.get(version_numbers, lock_version),
      snapshot_id: run.snapshot_id
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

  defp check_action_limit("new_run", project_id) do
    WorkOrders.limit_run_creation(project_id)
  end

  defp check_action_limit("activate_workflow", project_id) do
    WorkflowUsageLimiter.limit_workflow_activation(true, project_id)
  end

  defp check_action_limit("github_sync", project_id) do
    VersionControlUsageLimiter.limit_github_sync(project_id)
  end

  defp check_action_limit("ai_assistant", project_id) do
    Lightning.AiAssistant.Limiter.validate_quota(project_id)
  end

  defp check_action_limit("new_sandbox", project_id) do
    ProjectLimiter.limit_new_sandbox(project_id)
  end

  defp render_limits(project_id) do
    # Check run limit for initial context
    run_limit_result = check_action_limit("new_run", project_id)
    workflow_activation = check_action_limit("activate_workflow", project_id)
    github_sync = check_action_limit("github_sync", project_id)
    ai_assistant = check_action_limit("ai_assistant", project_id)
    new_sandbox = check_action_limit("new_sandbox", project_id)

    %{
      runs: render_limit_result(run_limit_result),
      workflow_activation: render_limit_result(workflow_activation),
      github_sync: render_limit_result(github_sync),
      ai_assistant: render_limit_result(ai_assistant),
      new_sandbox: render_limit_result(new_sandbox)
    }
  end

  defp render_limit_result(:ok) do
    %{
      allowed: true,
      message: nil
    }
  end

  defp render_limit_result({:error, _reason, message}) do
    %{
      allowed: false,
      message: message.text
    }
  end

  defp render_limit_result({:error, message}) do
    %{
      allowed: false,
      message: message.text
    }
  end
end
