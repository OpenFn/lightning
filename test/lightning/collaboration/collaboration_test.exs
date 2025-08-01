defmodule Lightning.Collaboration.Session do
  defstruct [:workflow_id, :shared_doc_pid, :cleanup_timer]

  alias Lightning.WorkflowCollaboration

  use GenServer

  require Logger

  @pg_scope :workflow_collaboration

  def start(workflow_id) do
    WorkflowCollaboration.Supervisor.start_child({__MODULE__, workflow_id})
  end

  # ---

  def init(workflow_id) do
    Logger.info("Starting session for workflow #{workflow_id}")

    # Just initialize the state, defer SharedDoc creation
    state = %__MODULE__{
      workflow_id: workflow_id,
      shared_doc_pid: nil,
      cleanup_timer: nil
    }

    # Send ourselves a message to start the SharedDoc after init completes
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
             auto_exit: false
           ]}

        case WorkflowCollaboration.Supervisor.start_child(child_spec) do
          {:ok, pid} ->
            # Register the SharedDoc with :pg so other sessions can find it
            Yex.Sync.SharedDoc.observe(pid)
            :pg.join(@pg_scope, workflow_id, pid)
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

  def start_link(workflow_id) do
    GenServer.start_link(__MODULE__, workflow_id)
  end

  def child_spec(workflow_id) do
    %{
      id: {__MODULE__, workflow_id},
      start: {__MODULE__, :start_link, [workflow_id]}
    }
  end

  def terminate(_reason, _state), do: :ok
end

defmodule Lightning.CollaborationTest do
  # Tests must be async: false because we put SharedDoc in a dynamic supervisor
  # that isn't owned by the test process. So we need our Ecto sandbox to be
  # in shared mode.
  use Lightning.DataCase, async: false

  alias Lightning.Collaboration.Session
  # we assume that the WorkflowCollaboration supervisor is up
  # that starts :pg with the :workflow_collaboration scope
  # and a dynamic supervisor called Lightning.WorkflowCollaboration

  describe "start/1" do
    test "when an existing SharedDoc doesn't exist" do
      workflow_id = Ecto.UUID.generate()

      {:ok, pid} = Session.start(workflow_id)

      # Wait a bit for the SharedDoc to be created asynchronously
      :timer.sleep(100)

      state = :sys.get_state(pid)
      assert state.workflow_id == workflow_id
      assert is_pid(state.shared_doc_pid)
    end

    test "when an existing SharedDoc does exist" do
      workflow_id = Ecto.UUID.generate()

      {:ok, pid1} = Session.start(workflow_id)
      state1 = :sys.get_state(pid1)

      # # Let SharedDoc start
      # :timer.sleep(100)

      {:ok, pid2} = Session.start(workflow_id)

      state2 = :sys.get_state(pid2)

      # Both should reference the same SharedDoc
      assert state1.shared_doc_pid == state2.shared_doc_pid
    end
  end

  describe "teardown" do
    test "when a session is stopped" do
      workflow_id = Ecto.UUID.generate()

      {:ok, pid} = Session.start(workflow_id)
      %Session{shared_doc_pid: shared_doc_pid} = :sys.get_state(pid)


      Lightning.WorkflowCollaboration.Supervisor.stop_child(pid)


      observer_processes = :sys.get_state(shared_doc_pid)
      |> Map.get(:assigns)
      |> Map.get(:observer_process)

      assert %{} == observer_processes

      # SharedDoc should still be alive because auto_exit: false
      assert Process.alive?(shared_doc_pid)
    end
  end
end
