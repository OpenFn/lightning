defmodule Lightning.Collaboration.Session do
  @moduledoc """
  Manages individual user sessions for collaborative workflow editing.

  A Session acts as a bridge between a parent process (typically a Phoenix
  channel) and a SharedDoc process that manages the Y.js CRDT document. Each
  user editing a workflow has their own Session process that handles:

  * User presence tracking via `Lightning.Workflows.Presence`
  * Bi-directional Y.js message routing between parent and SharedDoc
  * Connection management to existing SharedDoc processes via Registry lookup
  * Workflow document initialization with database data when needed
  * Cleanup when the parent process disconnects

  Sessions are temporary processes that monitor their parent and terminate
  when the parent disconnects, ensuring proper cleanup of presence tracking
  and SharedDoc observers.
  """
  use GenServer, restart: :temporary

  import LightningWeb.CoreComponents, only: [translate_error: 1]

  alias Lightning.Accounts.User
  alias Lightning.Collaboration.WorkflowSerializer
  alias Lightning.Workflows.Presence
  alias Yex.Sync.SharedDoc

  require Logger

  defstruct [
    :parent_pid,
    :parent_ref,
    :shared_doc_pid,
    :user,
    :workflow,
    :document_name
  ]

  @pg_scope :workflow_collaboration

  @type start_opts :: [
          workflow: Lightning.Workflows.Workflow.t(),
          user: User.t(),
          parent_pid: pid()
        ]

  @doc """
  Start a new session for a workflow.

  The session will be started as a child of the `Collaboration.Supervisor`.

  ## Options

  - `workflow` - The workflow struct to start the session for.
  - `user` - The user to start the session for.
  - `parent_pid` - The pid of the parent process.
     Defaults to the current process.
  """

  # @spec start(opts :: start_opts()) :: {:ok, pid()} | {:error, any()}
  # def start(opts) do
  #   opts = Keyword.put_new_lazy(opts, :parent_pid, fn -> self() end)

  #   Collaboration.Supervisor.start_child(child_spec(opts))
  # end

  def stop(session_pid) do
    GenServer.stop(session_pid)
  end

  def child_spec(opts) do
    {opts, args} =
      Keyword.put_new_lazy(opts, :session_id, fn -> Ecto.UUID.generate() end)
      |> Keyword.split_with(fn {k, _v} -> k in [:session_id, :name] end)

    {session_id, opts} = Keyword.pop!(opts, :session_id)

    %{
      id: {:session, session_id},
      start: {__MODULE__, :start_link, [args, opts]},
      restart: :temporary
    }
  end

  def start_link(args, opt \\ []) do
    GenServer.start_link(__MODULE__, args, opt)
  end

  @impl true
  def init(opts) do
    opts = Keyword.put_new_lazy(opts, :parent_pid, fn -> self() end)
    workflow = Keyword.fetch!(opts, :workflow)
    user = Keyword.fetch!(opts, :user)
    parent_pid = Keyword.fetch!(opts, :parent_pid)
    document_name = Keyword.fetch!(opts, :document_name)

    Logger.info("Starting session for document #{document_name}")

    parent_ref = Process.monitor(parent_pid)

    state = %__MODULE__{
      parent_pid: parent_pid,
      parent_ref: parent_ref,
      shared_doc_pid: nil,
      user: user,
      workflow: workflow,
      document_name: document_name
    }

    lookup_shared_doc(document_name)
    |> case do
      nil ->
        {:stop, {:error, :shared_doc_not_found}}

      shared_doc_pid ->
        SharedDoc.observe(shared_doc_pid)
        Logger.info("Joined SharedDoc for #{document_name}")

        # We track the user presence here so the the original WorkflowLive.Edit
        # can be stopped from editing the workflow when someone else is editing it.
        # Note: Presence tracking uses workflow.id, not document_name, because
        # presence is about showing who is editing the workflow, not which version
        Presence.track_user_presence(
          user,
          workflow.id,
          self()
        )

        {:ok, %{state | shared_doc_pid: shared_doc_pid}}
    end
  end

  @impl true
  def terminate(_reason, %{shared_doc_pid: shared_doc_pid} = state) do
    if state.parent_ref do
      Process.demonitor(state.parent_ref)
    end

    if shared_doc_pid && Process.alive?(shared_doc_pid) do
      SharedDoc.unobserve(shared_doc_pid)
    end

    Presence.untrack_user_presence(
      state.user,
      state.workflow.id,
      self()
    )

    :ok
  end

  def lookup_shared_doc(document_name) do
    case :pg.get_members(@pg_scope, document_name) do
      [] -> nil
      [shared_doc_pid | _] -> shared_doc_pid
    end
  end

  @doc """
  Get the current document.
  """
  def get_doc(session_pid) do
    GenServer.call(session_pid, :get_doc)
  end

  def stop_shared_doc(session_pid) do
    GenServer.call(session_pid, :stop_shared_doc)
  end

  def update_doc(session_pid, fun) do
    GenServer.call(session_pid, {:update_doc, fun})
  end

  def start_sync(session_pid, chunk) do
    GenServer.call(session_pid, {:start_sync, chunk})
  end

  def send_yjs_message(session_pid, chunk) do
    GenServer.call(session_pid, {:send_yjs_message, chunk})
  end

  @doc """
  Saves the current workflow state from the Y.Doc to the database.

  This function:
  1. Extracts the current workflow data from the SharedDoc's Y.Doc
  2. Converts Y.js types to Elixir maps suitable for Ecto
  3. Calls Lightning.Workflows.save_workflow/3 for validation and persistence
  4. Returns the saved workflow

  Note: This assumes all Y.js updates have been processed before this call,
  which is guaranteed by Phoenix Channel's synchronous message handling.

  ## Parameters
  - `session_pid`: The Session process PID
  - `user`: The user performing the save (for authorization and auditing)

  ## Returns
  - `{:ok, workflow}` - Successfully saved
  - `{:error, :workflow_deleted}` - Workflow has been deleted
  - `{:error, changeset}` - Validation or persistence error

  ## Examples

      iex> Session.save_workflow(session_pid, user)
      {:ok, %Workflow{}}

      iex> Session.save_workflow(session_pid, user)
      {:error, %Ecto.Changeset{}}
  """
  @spec save_workflow(pid(), Lightning.Accounts.User.t()) ::
          {:ok, Lightning.Workflows.Workflow.t()}
          | {:error,
             :workflow_deleted
             | :deserialization_failed
             | :internal_error
             | Ecto.Changeset.t()}
  def save_workflow(session_pid, user) do
    GenServer.call(session_pid, {:save_workflow, user}, 10_000)
  end

  @doc """
  Resets the workflow document to the latest snapshot from the database.

  This operation:
  1. Fetches the latest workflow from the database
  2. Clears all Y.Doc collections (jobs, edges, triggers arrays)
  3. Re-serializes the workflow to the Y.Doc
  4. Broadcasts updates to all connected clients via SharedDoc

  All collaborative editing history in the Y.Doc is preserved (operation log),
  but the document content is replaced with the database state.

  ## Parameters
  - `session_pid`: The Session process PID
  - `user`: The user performing the reset (for authorization logging)

  ## Returns
  - `{:ok, workflow}` - Successfully reset with updated workflow
  - `{:error, :workflow_deleted}` - Workflow has been deleted from database
  - `{:error, :internal_error}` - SharedDoc not available

  ## Examples

      iex> Session.reset_workflow(session_pid, user)
      {:ok, %Workflow{lock_version: 5}}

      iex> Session.reset_workflow(session_pid, user)
      {:error, :workflow_deleted}
  """
  @spec reset_workflow(pid(), Lightning.Accounts.User.t()) ::
          {:ok, Lightning.Workflows.Workflow.t()}
          | {:error, :workflow_deleted | :internal_error}
  def reset_workflow(session_pid, user) do
    GenServer.call(session_pid, {:reset_workflow, user}, 10_000)
  end

  @impl true
  def handle_call(:get_doc, _from, %{shared_doc_pid: shared_doc_pid} = state) do
    {:reply, SharedDoc.get_doc(shared_doc_pid), state}
  end

  @impl true
  def handle_call(
        :stop_shared_doc,
        _from,
        %{shared_doc_pid: shared_doc_pid} = state
      ) do
    send(shared_doc_pid, {:DOWN, nil, :process, self(), nil})
    {:reply, :ok, %{state | shared_doc_pid: nil}}
  end

  @impl true
  def handle_call(
        {:update_doc, fun},
        _from,
        %{shared_doc_pid: shared_doc_pid} = state
      ) do
    SharedDoc.update_doc(shared_doc_pid, fun)
    {:reply, :ok, state}
  end

  @impl true
  def handle_call(
        {:send_yjs_message, chunk},
        _from,
        %{shared_doc_pid: shared_doc_pid} = state
      ) do
    SharedDoc.send_yjs_message(shared_doc_pid, chunk)
    {:reply, :ok, state}
  end

  @impl true
  def handle_call(
        {:start_sync, chunk},
        from,
        %{shared_doc_pid: shared_doc_pid} = state
      ) do
    Logger.debug({:start_sync, from} |> inspect)
    SharedDoc.start_sync(shared_doc_pid, chunk)
    {:reply, :ok, state}
  end

  @impl true
  def handle_call({:save_workflow, user}, _from, state) do
    Logger.info("Saving workflow #{state.workflow.id} for user #{user.id}")

    with {:ok, doc} <- get_document(state),
         {:ok, workflow_data} <- deserialize_workflow(doc, state.workflow.id),
         {:ok, workflow} <- fetch_workflow(state.workflow),
         changeset <-
           Lightning.Workflows.change_workflow(workflow, workflow_data),
         {:ok, saved_workflow} <-
           Lightning.Workflows.save_workflow(changeset, user,
             skip_reconcile: true
           ),
         :ok <- merge_saved_workflow_into_ydoc(state, saved_workflow),
         {:ok, _job_cleanup_count} <-
           Lightning.AiAssistant.cleanup_unsaved_job_sessions(saved_workflow),
         {:ok, _workflow_cleanup_count} <-
           Lightning.AiAssistant.cleanup_unsaved_workflow_sessions(
             saved_workflow
           ) do
      Logger.info("Successfully saved workflow #{state.workflow.id}")
      {:reply, {:ok, saved_workflow}, %{state | workflow: saved_workflow}}
    else
      {:error, :no_shared_doc} ->
        Logger.error("Cannot save workflow #{state.workflow.id}: no shared doc")
        {:reply, {:error, :internal_error}, state}

      {:error, :deserialization_failed, reason} ->
        Logger.error(
          "Failed to deserialize workflow #{state.workflow.id}: #{inspect(reason)}"
        )

        {:reply, {:error, :deserialization_failed}, state}

      {:error, :workflow_deleted} ->
        Logger.warning(
          "Cannot save workflow #{state.workflow.id}: workflow deleted"
        )

        {:reply, {:error, :workflow_deleted}, state}

      {:error, %Ecto.Changeset{} = changeset} ->
        all_errors =
          Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
            Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
              opts
              |> Keyword.get(String.to_existing_atom(key), key)
              |> to_string()
            end)
          end)

        Logger.warning(fn ->
          """
          Failed to save workflow #{state.workflow.id}
          Top-level errors: #{inspect(changeset.errors)}
          All validation errors: #{inspect(all_errors)}
          """
        end)

        # Write validation errors to Y.Doc
        write_validation_errors_to_ydoc(state, changeset)

        {:reply, {:error, changeset}, state}
    end
  end

  @impl true
  def handle_call({:reset_workflow, user}, _from, state) do
    Logger.info("Resetting workflow #{state.workflow.id} for user #{user.id}")

    with {:ok, workflow} <- fetch_workflow(state.workflow),
         :ok <- clear_and_reset_doc(state, workflow) do
      Logger.info("Successfully reset workflow #{state.workflow.id}")
      {:reply, {:ok, workflow}, state}
    else
      {:error, :workflow_deleted} ->
        Logger.warning(
          "Cannot reset workflow #{state.workflow.id}: workflow deleted"
        )

        {:reply, {:error, :workflow_deleted}, state}

      {:error, :no_shared_doc} ->
        Logger.error("Cannot reset workflow #{state.workflow.id}: no shared doc")
        {:reply, {:error, :internal_error}, state}
    end
  end

  @impl true
  def handle_info({:yjs, reply, shared_doc_pid}, state) do
    Logger.debug(
      {:yjs, reply, shared_doc_pid}
      |> inspect(
        label: "Session :yjs",
        pretty: true,
        syntax_colors: IO.ANSI.syntax_colors()
      )
    )

    Map.get(state, :parent_pid) |> send({:yjs, reply})
    {:noreply, state}
  end

  # TODO: we need to have a strategy for handling the shared doc process crashing.
  # What should we do? We can't have all the sessions try and create a new one all at once.
  # and we want the front end to be able to still work, but show there is a problem?
  @impl true
  def handle_info(
        {:DOWN, ref, :process, _pid, _reason},
        %{parent_ref: parent_ref, shared_doc_pid: shared_doc_pid} = state
      ) do
    if ref == parent_ref do
      Process.demonitor(parent_ref)

      if shared_doc_pid && Process.alive?(shared_doc_pid) do
        SharedDoc.unobserve(shared_doc_pid)
      end

      {:stop, :normal, %{state | parent_ref: nil, shared_doc_pid: nil}}
    else
      {:noreply, state}
    end
  end

  @impl true
  def handle_info(any, state) do
    Logger.debug("Session received unknown message: #{inspect(any)}")
    {:noreply, state}
  end

  def initialize_workflow_document(
        doc,
        %Lightning.Workflows.Workflow{} = workflow
      ) do
    Logger.debug("Initializing SharedDoc with workflow data for #{workflow.id}")
    workflow = Lightning.Repo.preload(workflow, [:jobs, :edges, :triggers])
    WorkflowSerializer.serialize_to_ydoc(doc, workflow)
  end

  defp get_document(%{shared_doc_pid: nil}), do: {:error, :no_shared_doc}

  defp get_document(%{shared_doc_pid: pid}) do
    {:ok, SharedDoc.get_doc(pid)}
  end

  defp deserialize_workflow(doc, workflow_id) do
    data = WorkflowSerializer.deserialize_from_ydoc(doc, workflow_id)
    {:ok, data}
  rescue
    e ->
      {:error, :deserialization_failed, Exception.message(e)}
  end

  defp fetch_workflow(
         %{__meta__: %{state: :built}, lock_version: lock_version} = workflow
       )
       when lock_version > 0 do
    case Lightning.Workflows.get_workflow(workflow.id,
           include: [:jobs, :edges, :triggers]
         ) do
      nil -> {:error, :workflow_deleted}
      workflow -> {:ok, workflow}
    end
  end

  defp fetch_workflow(%{__meta__: %{state: :built}} = workflow) do
    workflow =
      workflow
      |> Map.put(:edges, %Ecto.Association.NotLoaded{
        __cardinality__: :many,
        __field__: :edges,
        __owner__: Lightning.Workflows.Workflow
      })
      |> Map.put(:jobs, %Ecto.Association.NotLoaded{
        __cardinality__: :many,
        __field__: :jobs,
        __owner__: Lightning.Workflows.Workflow
      })
      |> Map.put(:triggers, %Ecto.Association.NotLoaded{
        __cardinality__: :many,
        __field__: :triggers,
        __owner__: Lightning.Workflows.Workflow
      })

    {:ok, workflow}
  end

  defp fetch_workflow(workflow) do
    case Lightning.Workflows.get_workflow(workflow.id,
           include: [:jobs, :edges, :triggers]
         ) do
      nil -> {:error, :workflow_deleted}
      workflow -> {:ok, workflow}
    end
  end

  defp merge_saved_workflow_into_ydoc(
         %{shared_doc_pid: shared_doc_pid},
         workflow
       ) do
    SharedDoc.update_doc(shared_doc_pid, fn doc ->
      workflow_map = Yex.Doc.get_map(doc, "workflow")
      errors_map = Yex.Doc.get_map(doc, "errors")

      Yex.Doc.transaction(doc, "merge_saved_workflow", fn ->
        # Update lock version
        Yex.Map.set(workflow_map, "lock_version", workflow.lock_version)

        # Clear all errors after successful save
        clear_map(errors_map)
      end)
    end)
  end

  defp clear_and_reset_doc(%{shared_doc_pid: nil}, _workflow),
    do: {:error, :no_shared_doc}

  defp clear_and_reset_doc(%{shared_doc_pid: shared_doc_pid}, workflow) do
    SharedDoc.update_doc(shared_doc_pid, fn doc ->
      jobs_array = Yex.Doc.get_array(doc, "jobs")
      edges_array = Yex.Doc.get_array(doc, "edges")
      triggers_array = Yex.Doc.get_array(doc, "triggers")
      positions_map = Yex.Doc.get_map(doc, "positions")
      errors_map = Yex.Doc.get_map(doc, "errors")

      # Transaction 1: Clear all arrays and errors
      Yex.Doc.transaction(doc, "clear_workflow", fn ->
        clear_array(jobs_array)
        clear_array(edges_array)
        clear_array(triggers_array)
        clear_map(positions_map)
        clear_map(errors_map)
      end)

      WorkflowSerializer.serialize_to_ydoc(doc, workflow)
    end)

    :ok
  rescue
    error ->
      Logger.error("Error in clear_and_reset_doc: #{inspect(error)}")
      {:error, :internal_error}
  end

  defp clear_array(array) do
    length = Yex.Array.length(array)

    if length > 0 do
      Yex.Array.delete_range(array, 0, length)
    end
  end

  defp clear_map(map) do
    map
    |> Yex.Map.to_map()
    |> Enum.each(fn {key, _val} -> Yex.Map.delete(map, key) end)
  end

  # Write validation errors to Y.Doc errors map
  # This makes errors visible to all connected users
  defp write_validation_errors_to_ydoc(%{shared_doc_pid: nil}, _changeset) do
    Logger.warning("Cannot write errors: no shared doc")
    :ok
  end

  defp write_validation_errors_to_ydoc(
         %{shared_doc_pid: shared_doc_pid},
         changeset
       ) do
    # Format as plain maps (without Yex conversion yet)
    server_errors = format_changeset_errors_as_maps(changeset)

    Logger.debug(
      "write_validation_errors_to_ydoc: server_errors = #{inspect(server_errors)}"
    )

    SharedDoc.update_doc(shared_doc_pid, fn doc ->
      # Get errors map BEFORE transaction (avoid VM deadlock)
      errors_map = Yex.Doc.get_map(doc, "errors")

      # Read current errors to preserve client-side validation
      # Use to_json to get plain Elixir maps (to_map can return Yex.Map structs)
      current_errors = Yex.Map.to_json(errors_map)

      Logger.debug(
        "write_validation_errors_to_ydoc: current_errors = #{inspect(current_errors)}"
      )

      Yex.Doc.transaction(doc, "write_validation_errors", fn ->
        # Merge server errors with existing errors (both are plain maps)
        # Server errors take precedence over client errors for the same paths
        merged_errors = merge_server_errors(current_errors, server_errors)

        Logger.debug(
          "write_validation_errors_to_ydoc: merged_errors = #{inspect(merged_errors)}"
        )

        # Clear and rewrite with merged errors
        clear_map(errors_map)

        # Convert merged errors to Y.js compatible types before setting
        Enum.each(merged_errors, fn {field, value} ->
          yjs_value = convert_to_yjs_value(value)
          Yex.Map.set(errors_map, to_string(field), yjs_value)
        end)
      end)
    end)

    :ok
  rescue
    error ->
      Logger.error("Error writing validation errors to Y.Doc: #{inspect(error)}")

      :ok
  end

  # Merge server validation errors with existing errors (client-side)
  # Server errors take precedence for paths they validate
  defp merge_server_errors(current_errors, server_errors) do
    # Start with current errors (includes client errors)
    Map.merge(current_errors, server_errors, fn
      # For nested entity errors (jobs/triggers/edges), merge at entity and field level
      key, current_nested, server_nested
      when key in ["jobs", "triggers", "edges"] and is_map(current_nested) and
             is_map(server_nested) ->
        # Merge at entity ID level
        Map.merge(current_nested, server_nested, fn
          # For each entity ID, merge field errors
          _entity_id, current_fields, server_fields
          when is_map(current_fields) and is_map(server_fields) ->
            # Merge field-level errors: server wins for same field, both preserved for different fields
            Map.merge(current_fields, server_fields)

          # Server wins if types don't match (shouldn't happen in practice)
          _entity_id, _current_fields, server_fields ->
            server_fields
        end)

      # For workflow-level errors, merge field errors
      "workflow", current_workflow_errors, server_workflow_errors
      when is_map(current_workflow_errors) and is_map(server_workflow_errors) ->
        # Merge workflow field errors: server wins for same field
        Map.merge(current_workflow_errors, server_workflow_errors)

      # For simple values, server wins
      _key, _current, server ->
        server
    end)
  end

  # Format changeset errors as plain Elixir maps (for merging with client errors)
  # Does NOT convert to Yex types - that happens after merging
  defp format_changeset_errors_as_maps(changeset) do
    errors = extract_changeset_errors(changeset)

    # Separate workflow-level errors from entity errors
    {entity_errors, workflow_level_errors} =
      Map.split(errors, [:jobs, :triggers, :edges])

    # Nest workflow errors under 'workflow' key to match Y.Doc structure
    # Convert atom keys to strings for consistency with JSON representation
    result =
      if workflow_level_errors == %{} do
        entity_errors
      else
        Map.put(entity_errors, :workflow, workflow_level_errors)
      end

    # Convert atom keys to strings to match Y.Doc structure
    Map.new(result, fn {key, value} ->
      {to_string(key), atomize_map_keys_to_strings(value)}
    end)
  end

  # Helper to convert nested atom keys to strings
  defp atomize_map_keys_to_strings(value) when is_map(value) do
    Map.new(value, fn {k, v} ->
      {to_string(k), atomize_map_keys_to_strings(v)}
    end)
  end

  defp atomize_map_keys_to_strings(value), do: value

  defp extract_changeset_errors(changeset) do
    changeset.errors
    |> Enum.reverse()
    |> merge_keyword_keys()
    |> merge_related_keys(changeset)
  end

  defp merge_keyword_keys(keyword_list) do
    Enum.reduce(keyword_list, %{}, fn {key, val}, acc ->
      val = translate_error(val)
      Map.update(acc, key, [val], &[val | &1])
    end)
  end

  defp merge_related_keys(map, %Ecto.Changeset{
         changes: changes,
         data: %schema_module{}
       }) do
    fields =
      schema_module.__schema__(:associations) ++
        schema_module.__schema__(:embeds)

    Enum.reduce(fields, map, fn
      field, acc when field in [:jobs, :triggers, :edges] ->
        traverse_field_errors(acc, changes, field, fn
          field_changeset ->
            Ecto.Changeset.get_field(field_changeset, :id)
        end)

      field, acc ->
        traverse_field_errors(acc, changes, field, fn _ -> field end)
    end)
  end

  defp traverse_field_errors(acc, changes, field, child_name_func)
       when is_function(child_name_func, 1) do
    changesets =
      case Map.get(changes, field) do
        %{} = change ->
          [change]

        changes ->
          changes
      end

    if changesets do
      child = traverse_nested_changesets(changesets, child_name_func)

      if child == %{} do
        acc
      else
        Map.put(acc, field, child)
      end
    else
      acc
    end
  end

  defp traverse_nested_changesets(changesets, child_name_func) do
    Enum.reduce(changesets, %{}, fn changeset, acc ->
      child = extract_changeset_errors(changeset)

      if child == %{} do
        acc
      else
        child_name = changeset |> child_name_func.() |> to_string()
        Map.put(acc, child_name, child)
      end
    end)
  end

  # Recursively convert nested maps to Y.js compatible MapPrelim
  defp convert_to_yjs_value(value) when is_map(value) do
    Yex.MapPrelim.from(
      Map.new(value, fn {key, val} ->
        {to_string(key), convert_to_yjs_value(val)}
      end)
    )
  end

  # Convert lists to Y.js compatible ArrayPrelim
  defp convert_to_yjs_value(value) when is_list(value) do
    Yex.ArrayPrelim.from(Enum.map(value, &convert_to_yjs_value/1))
  end

  defp convert_to_yjs_value(value), do: value
end
