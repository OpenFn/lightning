defmodule Lightning.SessionTest do
  # Tests must be async: false because we put a SharedDoc in a dynamic supervisor
  # that isn't owned by the test process. So we need our Ecto sandbox to be
  # in shared mode.

  # We assume that the WorkflowCollaboration supervisor is up
  # that starts :pg with the :workflow_collaboration scope
  # and a dynamic supervisor called Lightning.WorkflowCollaboration

  use Lightning.DataCase, async: false

  import Eventually
  import Lightning.Factories

  alias Lightning.Collaboration.Session
  alias Lightning.Workflows.Workflow

  setup do
    user = insert(:user)
    {:ok, user: user}
  end

  defp start_session(opts) do
    {:ok, client} =
      Session.start(opts) |> Session.ready?()

    client
  end

  describe "start/1" do
    test "when an existing SharedDoc doesn't exist", %{user: user} do
      workflow_id = Ecto.UUID.generate()

      {:ok, pid} =
        Session.start(
          user: user,
          workflow_id: workflow_id
        )

      state = :sys.get_state(pid)
      assert state.workflow_id == workflow_id
      assert is_pid(state.shared_doc_pid)

      Session.stop(pid)

      refute_eventually(Process.alive?(state.shared_doc_pid))
    end

    test "and joining an existing session", %{user: user1} do
      user2 = insert(:user)
      workflow = insert(:simple_workflow)

      [parent1, parent2] = build_parents(2)

      [client_1, client_2] =
        for {parent, user} <- [{parent1, user1}, {parent2, user2}] do
          {:ok, client} =
            Session.start(
              user: user,
              workflow_id: workflow.id,
              parent_pid: parent
            )
            |> Session.ready?()

          client
        end

      # Check that both users are seen as online
      assert_eventually(
        length(
          Lightning.Workflows.Presence.list_presences_for(%Workflow{
            id: workflow.id
          })
        ) == 2
      )

      shared_doc_pids =
        [client_1, client_2]
        |> MapSet.new(fn client ->
          %Session{shared_doc_pid: shared_doc_pid} = :sys.get_state(client)
          shared_doc_pid
        end)

      assert MapSet.size(shared_doc_pids) == 1,
             "Expected exactly one shared doc pid, got #{inspect(shared_doc_pids)}"

      # Check there is only one SharedDoc process for this workflow
      assert_eventually(
        length(:pg.get_members(:workflow_collaboration, workflow.id)) == 1
      )

      Process.exit(parent2, :normal)
      # Check that the session exits when the parent exits
      refute_eventually(Process.alive?(client_2))

      Process.exit(parent1, :normal)
      refute_eventually(Process.alive?(client_1))

      shared_doc_pid = shared_doc_pids |> MapSet.to_list() |> List.first()
      refute_eventually(Process.alive?(shared_doc_pid))

      # TODO: I've enabled auto_exit: true, so this will be 0.
      # But we might want to control the cleanup ourselves, in which case
      # this will be > 0 until we stop the SharedDoc ourselves.
      assert_eventually(
        length(:pg.get_members(:workflow_collaboration, workflow.id)) == 0
      )
    end
  end

  describe "workflow initialization" do
    test "SharedDoc is initialized with workflow data", %{user: user} do
      # Create a workflow with jobs
      workflow =
        build(:complex_workflow, name: "Test Workflow")
        |> insert()

      # Start a session - this should initialize the SharedDoc with workflow data
      session_pid = start_session(user: user, workflow_id: workflow.id)

      # Send a message to allow :handle_continue to finish
      shared_doc = Session.get_doc(session_pid)

      # Check workflow map exists and has correct data
      workflow_map = Yex.Doc.get_map(shared_doc, "workflow")
      assert Yex.Map.fetch!(workflow_map, "id") == workflow.id
      assert Yex.Map.fetch!(workflow_map, "name") == "Test Workflow"

      # Check jobs array exists and has correct data
      jobs_array = Yex.Doc.get_array(shared_doc, "jobs")
      assert Yex.Array.length(jobs_array) == 7

      for i <- 0..(Yex.Array.length(jobs_array) - 1) do
        assert Enum.find(
                 workflow.jobs,
                 &(&1.id == Yex.Array.fetch!(jobs_array, i)["id"])
               ),
               "Job #{Yex.Array.fetch!(jobs_array, i)["id"]} not found in doc"
      end

      for job <- workflow.jobs do
        assert job_data = find_in_ydoc_array(jobs_array, job.id),
               "Job #{job.id} not found in doc"

        ~w(id name body)
        |> Enum.each(fn key ->
          assert get_ydoc_map_value(job_data, key) ==
                   get_expected_value(job, key)
        end)
      end

      edges_array = Yex.Doc.get_array(shared_doc, "edges")
      assert Yex.Array.length(edges_array) == 7

      for i <- 0..(Yex.Array.length(edges_array) - 1) do
        assert Enum.find(
                 workflow.edges,
                 &(&1.id == Yex.Array.fetch!(edges_array, i)["id"])
               ),
               "Edge #{Yex.Array.fetch!(edges_array, i)["id"]} not found in doc"
      end

      for workflow_edge <- workflow.edges do
        assert edge_data = find_in_ydoc_array(edges_array, workflow_edge.id),
               "Edge #{workflow_edge.id} not found in doc"

        ~w(enabled source_job_id source_trigger_id target_job_id
           condition_expression condition_label condition_type)
        |> Enum.each(fn key ->
          doc_value = edge_data[key]

          expected_value = get_expected_value(workflow_edge, key)

          assert doc_value == expected_value,
                 "Edge #{key} mismatch: expected #{expected_value |> inspect}, got #{doc_value |> inspect}"
        end)
      end

      triggers_array = Yex.Doc.get_array(shared_doc, "triggers")

      assert Yex.Array.length(triggers_array) == 1

      for trigger <- workflow.triggers do
        assert doc_trigger = find_in_ydoc_array(triggers_array, trigger.id),
               "Trigger #{trigger.id} not found in doc"

        ~w(cron_expression enabled has_auth_method id type)
        |> Enum.each(fn key ->
          doc_value = Yex.Map.fetch!(doc_trigger, key)

          expected_value = get_expected_value(trigger, key)

          assert doc_value == expected_value,
                 "Trigger #{key} mismatch: expected #{expected_value |> inspect}, got #{doc_value |> inspect}"
        end)
      end

      shared_doc_pid = :sys.get_state(session_pid).shared_doc_pid
      Session.stop(session_pid)
      refute_eventually(Process.alive?(shared_doc_pid))
    end

    test "existing SharedDoc is not reinitialized", %{user: user} do
      workflow = insert(:workflow, name: "Test Workflow")

      insert(:job, workflow: workflow, name: "Original Job", body: "original")

      # Start first session
      session1_pid = start_session(user: user, workflow_id: workflow.id)

      shared_doc_1 = Session.get_doc(session1_pid)

      Session.update_doc(session1_pid, fn doc ->
        workflow_map = Yex.Doc.get_map(doc, "workflow")
        Yex.Map.set(workflow_map, "name", "Modified Name")
      end)

      # Start second session - should connect to existing SharedDoc
      session2_pid = start_session(user: user, workflow_id: workflow.id)
      shared_doc_2 = Session.get_doc(session2_pid)

      assert shared_doc_1 == shared_doc_2

      # The modified name should still be there (not reinitialized)
      workflow_map = Yex.Doc.get_map(shared_doc_2, "workflow")
      assert Yex.Map.fetch!(workflow_map, "name") == "Modified Name"

      %Session{shared_doc_pid: shared_doc_pid} = :sys.get_state(session1_pid)

      Session.stop(session1_pid)
      Session.stop(session2_pid)

      refute_eventually(Process.alive?(shared_doc_pid))
    end

    test "client can sync workflow data from SharedDoc", %{user: user} do
      # Create workflow with jobs
      workflow = insert(:workflow, name: "Sync Test Workflow")

      job =
        insert(:job,
          workflow: workflow,
          name: "Sync Job",
          body: "console.log('sync')"
        )

      # Start session to initialize SharedDoc
      session_pid = start_session(user: user, workflow_id: workflow.id)

      %Session{shared_doc_pid: shared_doc_pid} = :sys.get_state(session_pid)

      # Simulate a client connecting and syncing
      Task.async(fn ->
        # Create a client document
        client_doc = Yex.Doc.new()

        # Observe the SharedDoc to receive sync messages
        Yex.Sync.SharedDoc.observe(shared_doc_pid)

        # Start sync process
        initiate_sync(shared_doc_pid, client_doc)
        receive_and_handle_replies(client_doc)

        # Verify client received workflow data
        workflow_map = Yex.Doc.get_map(client_doc, "workflow")
        jobs_array = Yex.Doc.get_array(client_doc, "jobs")

        assert Yex.Map.fetch!(workflow_map, "id") == workflow.id
        assert Yex.Map.fetch!(workflow_map, "name") == "Sync Test Workflow"

        jobs_data = Yex.Array.to_json(jobs_array)

        assert length(jobs_data) == 1
        assert List.first(jobs_data)["name"] == job.name
        assert List.first(jobs_data)["body"] == job.body
      end)
      |> Task.await()

      Session.stop(session_pid)
      refute_eventually(Process.alive?(shared_doc_pid))
    end
  end

  describe "reconnecting" do
    # This test recreates the issue we were having in the front end.
    # If the Workflow process/channel crashes, the frontend doc is still around
    # and when the frontend reconnects, it still has an active Doc.
    # So we need to make sure that when the Session process gets started again,
    # it doesn't create a new Doc from scratch, but rather loads the existing Doc
    # from persistence.

    test "frontend doc is still around", %{user: user} do
      workflow = insert(:simple_workflow)

      parent_pid = build_parent()

      session_pid =
        start_session(
          user: user,
          workflow_id: workflow.id,
          parent_pid: parent_pid
        )

      %Session{shared_doc_pid: shared_doc_pid} = :sys.get_state(session_pid)

      {:ok, client_pid} =
        GenServer.start(__MODULE__.TestClient, shared_doc_pid: shared_doc_pid)

      # Ensure handle_continue has finished
      :sys.get_state(client_pid)

      assert get_jobs(shared_doc_pid) |> length() == 1

      # Simulate a client disconnecting
      Process.exit(session_pid, :kill)
      refute_eventually(Process.alive?(session_pid))

      # TODO: we shouldn't need to unobserve explicitly here, if the Session
      # doesn't get to handle the DOWN message, then the SharedDoc will be left
      # running.
      GenServer.call(client_pid, :unobserve)
      refute_eventually(Process.alive?(shared_doc_pid))

      # Starting a new session
      session_pid =
        start_session(
          user: user,
          workflow_id: workflow.id,
          parent_pid: parent_pid
        )

      %Session{shared_doc_pid: shared_doc_pid} = :sys.get_state(session_pid)

      GenServer.call(client_pid, {:observe, shared_doc_pid})

      jobs = GenServer.call(client_pid, :get_jobs)
      assert length(jobs) == 1

      Session.stop(session_pid)
      GenServer.stop(client_pid)
      refute_eventually(Process.alive?(session_pid))
      refute_eventually(Process.alive?(shared_doc_pid))
    end
  end

  defp initiate_sync(shared_doc, client_doc) do
    {:ok, step1} = Yex.Sync.get_sync_step1(client_doc)
    local_message = Yex.Sync.message_encode!({:sync, step1})
    Yex.Sync.SharedDoc.start_sync(shared_doc, local_message)
  end

  # Helper function for sync tests (similar to SharedDoc test pattern)
  defp receive_and_handle_replies(doc, timeout \\ 100) do
    receive do
      {:yjs, reply, proc} ->
        case Yex.Sync.message_decode(reply) do
          {:ok, {:sync, sync_message}} ->
            case Yex.Sync.read_sync_message(sync_message, doc, proc) do
              :ok ->
                :ok

              {:ok, reply} ->
                Yex.Sync.SharedDoc.send_yjs_message(
                  proc,
                  Yex.Sync.message_encode!({:sync, reply})
                )
            end

          _ ->
            :ok
        end

        receive_and_handle_replies(doc, timeout)
    after
      # If we don't receive a message, we're done
      timeout -> :ok
    end
  end

  describe "teardown" do
    test "when a session is stopped", %{user: user1} do
      workflow_id = Ecto.UUID.generate()
      user2 = insert(:user)
      user3 = insert(:user)

      [{client1, parent1}, {client2, parent2}, {client3, _parent3}] =
        Enum.map([user1, user2, user3], fn user ->
          parent = build_parent()

          {:ok, client} =
            Session.start(
              user: user,
              workflow_id: workflow_id,
              parent_pid: parent
            )
            |> Session.ready?()

          {client, parent}
        end)

      shared_doc_pids =
        [client1, client2, client3]
        |> MapSet.new(fn client ->
          %Session{shared_doc_pid: shared_doc_pid} = :sys.get_state(client)
          shared_doc_pid
        end)

      assert MapSet.size(shared_doc_pids) == 1,
             "Expected exactly one shared doc pid, got #{inspect(shared_doc_pids)}"

      %Session{shared_doc_pid: shared_doc_pid} = :sys.get_state(client3)

      # Calls Session.terminate
      Session.stop(client3)
      refute_eventually(Process.alive?(client3))
      assert Process.alive?(shared_doc_pid)

      Process.exit(parent2, :normal)
      refute_eventually(Process.alive?(client2))
      assert Process.alive?(shared_doc_pid)

      Process.exit(parent1, :normal)
      refute_eventually(Process.alive?(client1))
      refute_eventually(Process.alive?(shared_doc_pid))

      # If we disable auto_exit, so we can control cleanup ourselves,
      # we can check that the SharedDoc is no longer being observed like this
      # assert_eventually(
      #   :sys.get_state(shared_doc_pid)
      #   |> Map.get(:assigns)
      #   |> Map.get(:observer_process) ==
      #     %{}
      # )
    end
  end

  defp get_expected_value(model, key) do
    Map.fetch!(model, key |> String.to_existing_atom())
    |> case do
      v when is_nil(v) or is_boolean(v) ->
        v

      v when is_atom(v) ->
        v |> to_string()

      v ->
        v
    end
  end

  defp get_ydoc_map_value(map, key) do
    Yex.Map.fetch!(map, key)
    |> case do
      %Yex.Text{} = text ->
        Yex.Text.to_string(text)

      v ->
        v
    end
  end

  defp find_in_ydoc_array(array, id) do
    array
    |> Yex.Array.to_list()
    |> Enum.find(fn item ->
      Yex.Map.fetch!(item, "id") == id
    end)
  end

  defp build_parent() do
    spawn_link(fn ->
      Process.flag(:trap_exit, true)

      receive do
        {:EXIT, _pid, reason} ->
          IO.inspect(reason, label: "parent exit")
          :ok

        any ->
          IO.inspect(any,
            label: "WARNING: parent received unknown message: exiting"
          )

          :ok
      end
    end)
  end

  defp build_parents(count) do
    for _ <- 1..count do
      build_parent()
    end
  end

  def get_jobs(shared_doc_pid) do
    Yex.Sync.SharedDoc.get_doc(shared_doc_pid)
    |> Yex.Doc.get_array("jobs")
    |> Yex.Array.to_list()
  end

  defmodule TestClient do
    use GenServer
    alias Lightning.Collaboration.Utils

    def init(opts) do
      shared_doc_pid = opts[:shared_doc_pid]
      client_doc = Yex.Doc.new()

      {:ok, %{client_doc: client_doc, shared_doc_pid: shared_doc_pid},
       {:continue, :sync}}
    end

    def handle_continue(:sync, state) do
      # Observe the SharedDoc to receive sync messages
      observe(state.shared_doc_pid)
      start_sync(state.shared_doc_pid, state.client_doc)

      {:noreply, state}
    end

    defp observe(shared_doc_pid) do
      Yex.Sync.SharedDoc.observe(shared_doc_pid)
    end

    defp start_sync(shared_doc_pid, client_doc) do
      {:ok, step1} = Yex.Sync.get_sync_step1(client_doc)
      local_message = Yex.Sync.message_encode!({:sync, step1})
      Yex.Sync.SharedDoc.start_sync(shared_doc_pid, local_message)
    end

    def handle_call(:unobserve, _from, state) do
      Yex.Sync.SharedDoc.unobserve(state.shared_doc_pid)
      {:reply, :ok, state}
    end

    def handle_call({:observe, shared_doc_pid}, _from, state) do
      observe(shared_doc_pid)
      start_sync(shared_doc_pid, state.client_doc)
      {:reply, :ok, %{state | shared_doc_pid: shared_doc_pid}}
    end

    def handle_call(:get_doc, _from, state) do
      {:reply, state.client_doc, state}
    end

    def handle_call(:get_jobs, _from, state) do
      {:reply, Lightning.SessionTest.get_jobs(state.shared_doc_pid), state}
    end

    def handle_info({:yjs, msg, proc}, state) do
      # proc is usually the SharedDoc process.

      case Yex.Sync.message_decode(msg) do
        {:ok, {:sync, sync_message}} ->
          case Yex.Sync.read_sync_message(
                 sync_message,
                 state.client_doc,
                 state.shared_doc_pid
               ) do
            :ok ->
              IO.inspect(msg |> Utils.decipher_message(),
                label: "handle_info :yjs :ok"
              )

              {:noreply, state}

            {:ok, reply} ->
              IO.inspect(msg |> Utils.decipher_message(),
                label: "handle_info :yjs :reply"
              )

              Yex.Sync.SharedDoc.send_yjs_message(
                proc,
                Yex.Sync.message_encode!({:sync, reply})
              )

              {:noreply, state}
          end

        _ ->
          IO.inspect(msg |> Utils.decipher_message(),
            label: "handle_info :yjs"
          )

          {:noreply, state}
      end
    end

    def terminate(_reason, state) do
      Yex.Sync.SharedDoc.unobserve(state.shared_doc_pid)
      :ok
    end
  end
end
