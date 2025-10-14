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

  alias Lightning.Accounts.User
  alias Lightning.Collaboration.Registry
  alias Lightning.Collaboration.WorkflowSerializer
  alias Lightning.Workflows.Presence
  alias Yex.Sync.SharedDoc

  require Logger

  defstruct [:parent_pid, :parent_ref, :shared_doc_pid, :user, :workflow]

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

  # ----------------------------------------------------------------------------

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

    Logger.info("Starting session for workflow #{workflow.id}")

    parent_ref = Process.monitor(parent_pid)

    # Just initialize the state, defer SharedDoc creation
    state = %__MODULE__{
      parent_pid: parent_pid,
      parent_ref: parent_ref,
      shared_doc_pid: nil,
      user: user,
      workflow: workflow
    }

    Registry.whereis({:shared_doc, "workflow:#{workflow.id}"})
    |> case do
      nil ->
        {:stop, {:error, :shared_doc_not_found}}

      shared_doc_pid ->
        SharedDoc.observe(shared_doc_pid)
        Logger.info("Joined SharedDoc for workflow #{workflow.id}")

        # We track the user presence here so the the original WorkflowLive.Edit
        # can be stopped from editing the workflow when someone else is editing it.
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

  # ----------------------------------------------------------------------------

  def lookup_shared_doc(workflow_id) do
    case :pg.get_members(@pg_scope, workflow_id) do
      [] -> nil
      [shared_doc_pid | _] -> shared_doc_pid
    end
  end

  # ----------------------------------------------------------------------------

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

  # ----------------------------------------------------------------------------

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

  # Comes from the parent process, we forward it on to the SharedDoc.
  # The SharedDoc will send a message back via the :yjs message.
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
        Logger.warning(
          "Failed to save workflow #{state.workflow.id}: #{inspect(changeset.errors)}"
        )

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

  # Comes from the SharedDoc, for changes coming from the SharedDoc
  # and we forward it on to the parent process.
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

  # ----------------------------------------------------------------------------

  def initialize_workflow_document(
        doc,
        %Lightning.Workflows.Workflow{} = workflow
      ) do
    Logger.debug("Initializing SharedDoc with workflow data for #{workflow.id}")
    workflow = Lightning.Repo.preload(workflow, [:jobs, :edges, :triggers])
    WorkflowSerializer.serialize_to_ydoc(doc, workflow)
  end

  # Private helper functions

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

  defp fetch_workflow(%{__meta__: %{state: :built}} = workflow) do
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

  defp clear_and_reset_doc(%{shared_doc_pid: nil}, _workflow),
    do: {:error, :no_shared_doc}

  defp clear_and_reset_doc(%{shared_doc_pid: shared_doc_pid}, workflow) do
    SharedDoc.update_doc(shared_doc_pid, fn doc ->
      # Get all Yex collections BEFORE transaction (critical for avoiding VM
      # deadlock)
      jobs_array = Yex.Doc.get_array(doc, "jobs")
      edges_array = Yex.Doc.get_array(doc, "edges")
      triggers_array = Yex.Doc.get_array(doc, "triggers")

      # Transaction 1: Clear all arrays
      Yex.Doc.transaction(doc, "clear_workflow", fn ->
        clear_array(jobs_array)
        clear_array(edges_array)
        clear_array(triggers_array)
      end)

      # Transaction 2: Re-serialize workflow (WorkflowSerializer does its own
      # transaction)
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
end
