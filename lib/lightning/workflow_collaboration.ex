defmodule Lightning.WorkflowCollaboration do
  @moduledoc """
  OTP system for managing collaborative workflow editing with proper process lifecycle.

  Uses :pg for fault-tolerant process discovery and Yex.Sync.SharedDoc for Y.js protocol.
  Follows "Designing Elixir Systems with OTP" patterns for robust collaboration.

  Architecture:
  - WorkflowCollaborator: Manages user connections and process lifecycle
  - Yex.Sync.SharedDoc: Handles Y.js CRDT protocol
  - :pg groups: Fault-tolerant process discovery
  - DynamicSupervisor: Process management
  """

  use GenServer
  require Logger

  alias Yex.Sync.SharedDoc

  @pg_scope :workflow_collaboration
  # Wait 60s before cleanup in case of reconnects
  @cleanup_delay_ms 60_000

  defstruct [
    :workflow_id,
    :shared_doc_pid,
    # %{liveview_pid => %{user_id: id, monitor_ref: ref, joined_at: time}}
    :connected_users,
    :cleanup_timer
  ]

  # Client API

  @doc """
  Join a collaborative workflow session.

  Finds or starts a collaboration process for the workflow using :pg.
  Returns {:ok, collaborator_pid, initial_doc_state} or {:error, reason}.
  """
  def join_workflow(workflow_id, user_id) do
    Logger.info("Attempting to join workflow #{workflow_id} for user #{user_id}")

    case find_or_start_collaborator(workflow_id) do
      {:ok, collaborator_pid} ->
        Logger.info(
          "Found/started collaborator #{inspect(collaborator_pid)} for workflow #{workflow_id}"
        )

        case GenServer.call(collaborator_pid, {:join_user, user_id}) do
          {:ok, doc_state} ->
            {:ok, collaborator_pid, doc_state}

          error ->
            Logger.error(
              "Failed to join user #{user_id} to collaborator: #{inspect(error)}"
            )

            error
        end

      error ->
        Logger.error(
          "Failed to find/start collaborator for workflow #{workflow_id}: #{inspect(error)}"
        )

        error
    end
  end

  @doc """
  Leave a collaborative workflow session.
  """
  def leave_workflow(collaborator_pid, liveview_pid) do
    GenServer.cast(collaborator_pid, {:leave_process, liveview_pid})
  end

  @doc """
  Send a Y.js message to the collaborative document.
  """
  def send_yjs_message(collaborator_pid, message) do
    GenServer.call(collaborator_pid, {:yjs_message, message})
  end

  @doc """
  Subscribe to Y.js updates from the document.
  """
  def observe_document(collaborator_pid) do
    GenServer.call(collaborator_pid, :observe)
  end

  @doc """
  Get the current document state.
  """
  def get_document(collaborator_pid) do
    GenServer.call(collaborator_pid, :get_doc)
  end

  @doc """
  Update the document with the given function.
  """
  def update_document(collaborator_pid, fun, timeout \\ 5000) do
    GenServer.call(collaborator_pid, {:update_doc, fun}, timeout)
  end

  # Process Discovery using :pg

  defp find_or_start_collaborator(workflow_id) do
    Logger.info("Looking for existing collaborators for workflow #{workflow_id}")

    case :pg.get_members(@pg_scope, workflow_id) do
      [] ->
        Logger.info(
          "No existing collaborators found, starting new one for workflow #{workflow_id}"
        )

        # No processes exist, start one locally
        start_local_collaborator(workflow_id)

      processes ->
        Logger.info(
          "Found existing collaborators: #{inspect(processes)} for workflow #{workflow_id}"
        )

        # Use existing process, prefer local for performance
        select_best_process(workflow_id, processes)
    end
  end

  defp select_best_process(_workflow_id, processes) do
    local_processes = Enum.filter(processes, &(node(&1) == node()))

    case local_processes do
      [pid | _] ->
        # Use local process for better performance
        {:ok, pid}

      [] ->
        # Use any available process
        {:ok, Enum.random(processes)}
    end
  end

  defp start_local_collaborator(workflow_id) do
    Logger.info(
      "Attempting to start local collaborator for workflow #{workflow_id}"
    )

    case Lightning.WorkflowCollaboration.Supervisor.start_collaboration(
           workflow_id
         ) do
      {:ok, pid} ->
        Logger.info(
          "Successfully started collaborator #{inspect(pid)} for workflow #{workflow_id}"
        )

        {:ok, pid}

      {:error, {:already_started, pid}} ->
        Logger.info(
          "Collaborator already started #{inspect(pid)} for workflow #{workflow_id}"
        )

        {:ok, pid}

      error ->
        Logger.error(
          "Failed to start collaborator for workflow #{workflow_id}: #{inspect(error)}"
        )

        error
    end
  end

  # GenServer Implementation

  def start_link(workflow_id) do
    GenServer.start_link(__MODULE__, workflow_id)
  end

  @impl true
  def init(workflow_id) do
    # Join the process group for discovery
    :pg.join(@pg_scope, workflow_id, self())

    # Start the SharedDoc with auto_exit: false (we control lifecycle)
    {:ok, shared_doc_pid} =
      SharedDoc.start_link(
        doc_name: "workflow:#{workflow_id}",
        # We control when to exit
        auto_exit: false,
        persistence: Lightning.WorkflowCollaboration.Persistence
      )

    # Initialize document with default content if it's empty
    initialize_document_if_empty(shared_doc_pid)

    # Monitor the SharedDoc
    Process.monitor(shared_doc_pid)

    state = %__MODULE__{
      workflow_id: workflow_id,
      shared_doc_pid: shared_doc_pid,
      connected_users: %{},
      cleanup_timer: nil
    }

    Logger.info("Started workflow collaborator for #{workflow_id}")
    {:ok, state}
  end

  @impl true
  def handle_call({:join_user, user_id}, {from_pid, _tag}, state) do
    # Cancel any cleanup timer
    state = cancel_cleanup_timer(state)

    # Monitor the user process
    monitor_ref = Process.monitor(from_pid)

    # Add LiveView process to connected list (using PID as key to support multiple tabs per user)
    connected_users =
      Map.put(state.connected_users, from_pid, %{
        user_id: user_id,
        monitor_ref: monitor_ref,
        joined_at: DateTime.utc_now()
      })

    # Get current document state for initial sync
    {:ok, doc_state} =
      SharedDoc.get_doc(state.shared_doc_pid)
      |> Yex.encode_state_as_update()

    new_state = %{state | connected_users: connected_users}

    Logger.info(
      "User #{user_id} (PID #{inspect(from_pid)}) joined workflow #{state.workflow_id}"
    )

    {:reply, {:ok, doc_state}, new_state}
  end

  @impl true
  def handle_call({:yjs_message, message}, _from, state) do
    result = SharedDoc.send_yjs_message(state.shared_doc_pid, message)
    {:reply, result, state}
  end

  @impl true
  def handle_call(:observe, {_from_pid, _tag}, state) do
    result = SharedDoc.observe(state.shared_doc_pid)
    {:reply, result, state}
  end

  @impl true
  def handle_call(:get_doc, _from, state) do
    doc = SharedDoc.get_doc(state.shared_doc_pid)
    {:reply, doc, state}
  end

  @impl true
  def handle_call({:update_doc, fun}, _from, state) do
    result = SharedDoc.update_doc(state.shared_doc_pid, fun)
    {:reply, result, state}
  end

  @impl true
  def handle_cast({:leave_process, liveview_pid}, state) do
    case Map.get(state.connected_users, liveview_pid) do
      %{user_id: user_id, monitor_ref: monitor_ref} ->
        # Demonitor this specific process
        Process.demonitor(monitor_ref)

        # Remove only this specific PID
        connected_users = Map.delete(state.connected_users, liveview_pid)
        new_state = %{state | connected_users: connected_users}

        Logger.info(
          "User #{user_id} (PID #{inspect(liveview_pid)}) left workflow #{state.workflow_id}"
        )

        # Check if we should cleanup
        maybe_schedule_cleanup(new_state)

      nil ->
        # PID not found, nothing to do
        {:noreply, state}
    end
  end

  @impl true
  def handle_info({:DOWN, _monitor_ref, :process, pid, reason}, state) do
    cond do
      pid == state.shared_doc_pid ->
        Logger.error(
          "SharedDoc died for workflow #{state.workflow_id}: #{inspect(reason)}"
        )

        {:stop, :shared_doc_died, state}

      true ->
        # Handle LiveView process disconnection by PID
        case Map.get(state.connected_users, pid) do
          %{user_id: user_id} ->
            connected_users = Map.delete(state.connected_users, pid)
            new_state = %{state | connected_users: connected_users}

            Logger.info(
              "User #{user_id} (PID #{inspect(pid)}) disconnected from workflow #{state.workflow_id}"
            )

            # Check if we should cleanup
            maybe_schedule_cleanup(new_state)

          nil ->
            # PID not found in our connected users, ignore
            {:noreply, state}
        end
    end
  end

  @impl true
  def handle_info({:yjs, message, sender_pid}, state) do
    # Forward Y.js messages to all connected LiveView processes
    Enum.each(state.connected_users, fn {liveview_pid, _user_info} ->
      send(liveview_pid, {:yjs, message, sender_pid})
    end)

    {:noreply, state}
  end

  @impl true
  def handle_info(:cleanup_timeout, state) do
    if map_size(state.connected_users) == 0 do
      Logger.info(
        "Cleaning up workflow collaborator #{state.workflow_id} - no users"
      )

      {:stop, :normal, state}
    else
      # Users reconnected, cancel cleanup
      {:noreply, %{state | cleanup_timer: nil}}
    end
  end

  @impl true
  def terminate(_reason, state) do
    # Leave the process group
    :pg.leave(@pg_scope, state.workflow_id, self())

    # The SharedDoc will handle its own cleanup
    Logger.info("Workflow collaborator #{state.workflow_id} terminating")
    :ok
  end

  # Private helpers

  defp maybe_schedule_cleanup(state) do
    if map_size(state.connected_users) == 0 do
      # Schedule cleanup after delay to handle quick reconnects
      cleanup_timer =
        Process.send_after(self(), :cleanup_timeout, @cleanup_delay_ms)

      {:noreply, %{state | cleanup_timer: cleanup_timer}}
    else
      {:noreply, state}
    end
  end

  defp cancel_cleanup_timer(%{cleanup_timer: nil} = state), do: state

  defp cancel_cleanup_timer(%{cleanup_timer: timer} = state) do
    Process.cancel_timer(timer)
    %{state | cleanup_timer: nil}
  end

  # Initialize document with default content if it's empty
  defp initialize_document_if_empty(shared_doc_pid) do
    SharedDoc.update_doc(shared_doc_pid, fn doc ->
      # Check if counter map already has a value
      counter_map = Yex.Doc.get_map(doc, "counter_data")

      case Yex.Map.fetch(counter_map, "value") do
        {:ok, _existing_value} ->
          # Already initialized, do nothing
          :ok

        :error ->
          # Initialize with defaults
          timestamp = DateTime.utc_now() |> DateTime.to_iso8601()
          Yex.Map.set(counter_map, "value", 0)
          Yex.Map.set(counter_map, "last_updated", timestamp)
      end
    end)
  end
end
