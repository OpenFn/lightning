defmodule Lightning.Collaboration.Session do
  use GenServer
  alias Lightning.Collaboration
  require Logger

  defstruct [:workflow_id, :shared_doc_pid, :cleanup_timer, :parent_pid]

  @pg_scope :workflow_collaboration

  def start(workflow_id) do
    GenServer.start_link(__MODULE__,
      workflow_id: workflow_id,
      parent_pid: self()
    )
  end

  # ---

  def init(opts) do
    workflow_id = Keyword.fetch!(opts, :workflow_id)
    parent_pid = Keyword.fetch!(opts, :parent_pid)

    Logger.info("Starting session for workflow #{workflow_id}")

    # Just initialize the state, defer SharedDoc creation
    state = %__MODULE__{
      workflow_id: workflow_id,
      shared_doc_pid: nil,
      cleanup_timer: nil,
      parent_pid: parent_pid
    }

    {:ok, state, {:continue, :start_shared_doc}}
  end

  def handle_continue(:start_shared_doc, %{workflow_id: workflow_id} = state) do
    case :pg.get_members(@pg_scope, workflow_id) do
      [] ->
        Logger.info("No existing SharedDoc found for workflow #{workflow_id}")

        child_spec =
          {Yex.Sync.SharedDoc,
           [
             doc_name: "workflow:#{workflow_id}",
             auto_exit: true
           ]}

        case Collaboration.Supervisor.start_child(child_spec) do
          {:ok, pid} ->
            :pg.join(@pg_scope, workflow_id, pid)
            # Register the SharedDoc with :pg so other sessions can find it
            Yex.Sync.SharedDoc.observe(pid)
            {:noreply, %{state | shared_doc_pid: pid}}

          {:error, {:already_started, pid}} ->
            {:noreply, %{state | shared_doc_pid: pid}}

          error ->
            Logger.error(
              "Failed to start SharedDoc for workflow #{workflow_id}: #{inspect(error)}"
            )

            {:stop, {:shutdown, :shared_doc_start_failed}, state}
        end

      [shared_doc_pid | _] ->
        Logger.info("Existing SharedDoc found for workflow #{workflow_id}")
        Yex.Sync.SharedDoc.observe(shared_doc_pid)
        {:noreply, %{state | shared_doc_pid: shared_doc_pid}}
    end
  end

  # TODO: we need to have a strategy for handling the shared doc process crashing.
  # What should we do? We can't have all the sessions try and create a new one all at once.
  # and we want the front end to be able to still work, but show there is a problem?
  # @impl true
  # def handle_info(
  #       {:DOWN, _ref, :process, _pid, _reason},
  #       socket
  #     ) do
  #   {:stop, {:error, "remote process crash"}, socket}
  # end

  def terminate(reason, _state) do
    Logger.debug("Session terminating: #{inspect({reason})}")
    :ok
  end

  def stop(session_pid) do
    GenServer.stop(session_pid)
  end

  @doc """
  Get the current document state.
  """
  def get_document(session_pid) do
    GenServer.call(session_pid, :get_doc)
  end

  def start_sync(session_pid, chunk) do
    GenServer.call(session_pid, {:yjs_sync, chunk})
  end

  def send_yjs_message(session_pid, chunk) do
    GenServer.call(session_pid, {:yjs, chunk})
  end

  def handle_call(:get_doc, _from, %{shared_doc_pid: shared_doc_pid} = state) do
    {:reply, Yex.Sync.SharedDoc.get_doc(shared_doc_pid), state}
  end

  def handle_call(
        {:yjs, chunk},
        _from,
        %{shared_doc_pid: shared_doc_pid} = state
      ) do
    Yex.Sync.SharedDoc.send_yjs_message(shared_doc_pid, chunk)
    {:reply, :ok, state}
  end

  def handle_call(
        {:yjs_sync, chunk},
        _from,
        %{shared_doc_pid: shared_doc_pid} = state
      ) do
    Yex.Sync.SharedDoc.start_sync(shared_doc_pid, chunk)
    {:reply, :ok, state}
  end

  def handle_info({:yjs, reply, _shared_doc_pid}, state) do
    Map.get(state, :parent_pid) |> send({:yjs, reply})
    {:noreply, state}
  end
end
