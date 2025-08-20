defmodule Lightning.SessionTest do
  # Tests must be async: false because we put a SharedDoc in a dynamic supervisor
  # that isn't owned by the test process. So we need our Ecto sandbox to be
  # in shared mode.
  use Lightning.DataCase, async: false

  import Eventually
  import Lightning.Factories

  alias Lightning.Collaboration.Session
  # we assume that the WorkflowCollaboration supervisor is up
  # that starts :pg with the :workflow_collaboration scope
  # and a dynamic supervisor called Lightning.WorkflowCollaboration

  describe "start/1" do
    test "when an existing SharedDoc doesn't exist" do
      workflow_id = Ecto.UUID.generate()

      {:ok, pid} = Session.start(workflow_id) |> Session.ready?()

      state = :sys.get_state(pid)
      assert state.workflow_id == workflow_id
      assert is_pid(state.shared_doc_pid)
    end

    test "when an existing SharedDoc does exist" do
      workflow_id = Ecto.UUID.generate()

      {:ok, pid1} = Session.start(workflow_id) |> Session.ready?()

      state1 = :sys.get_state(pid1)

      {:ok, pid2} = Session.start(workflow_id) |> Session.ready?()

      state2 = :sys.get_state(pid2)

      # Both should reference the same SharedDoc
      assert state1.shared_doc_pid == state2.shared_doc_pid
    end
  end

  describe "joining" do
    test "with start_link" do
      workflow = insert(:simple_workflow)

      client_1 =
        Task.async(fn ->
          {:ok, pid} = Session.start(workflow.id) |> Session.ready?()

          pid
        end)

      client_1 = Task.await(client_1)

      client_2 =
        Task.async(fn ->
          {:ok, pid} = Session.start(workflow.id) |> Session.ready?()

          pid
        end)

      client_2 = Task.await(client_2)

      GenServer.stop(client_2)
      Process.alive?(client_2)

      GenServer.stop(client_1)
      Process.alive?(client_1)

      # TODO: I've enabled auto_exit: true, so this should be 0.
      # But we might want to control the cleanup ourselves, in which case
      # this will be > 0.
      assert_eventually(
        length(:pg.get_members(:workflow_collaboration, workflow.id)) == 0
      )

      # IO.inspect({session_one, session_two})
    end
  end

  describe "workflow initialization" do
    test "SharedDoc is initialized with workflow data" do
      # Create a workflow with jobs
      workflow =
        build(:complex_workflow, name: "Test Workflow")
        |> insert()

      # Start a session - this should initialize the SharedDoc with workflow data
      {:ok, session_pid} = Session.start(workflow.id) |> Session.ready?()

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
    end

    test "existing SharedDoc is not reinitialized" do
      workflow = insert(:workflow, name: "Test Workflow")

      insert(:job, workflow: workflow, name: "Original Job", body: "original")

      # Start first session
      {:ok, session1_pid} = Session.start(workflow.id) |> Session.ready?()

      shared_doc_1 = Session.get_doc(session1_pid)

      Session.update_doc(session1_pid, fn doc ->
        workflow_map = Yex.Doc.get_map(doc, "workflow")
        Yex.Map.set(workflow_map, "name", "Modified Name")
      end)

      # Start second session - should connect to existing SharedDoc
      {:ok, session2_pid} = Session.start(workflow.id) |> Session.ready?()
      shared_doc_2 = Session.get_doc(session2_pid)

      assert shared_doc_1 == shared_doc_2

      # The modified name should still be there (not reinitialized)
      workflow_map = Yex.Doc.get_map(shared_doc_2, "workflow")
      assert Yex.Map.fetch!(workflow_map, "name") == "Modified Name"
    end

    test "client can sync workflow data from SharedDoc" do
      # Create workflow with jobs
      workflow = insert(:workflow, name: "Sync Test Workflow")

      job =
        insert(:job,
          workflow: workflow,
          name: "Sync Job",
          body: "console.log('sync')"
        )

      # Start session to initialize SharedDoc
      {:ok, session_pid} = Session.start(workflow.id) |> Session.ready?()

      state = :sys.get_state(session_pid)
      shared_doc_pid = state.shared_doc_pid

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
    test "when a session is stopped" do
      workflow_id = Ecto.UUID.generate()

      {:ok, pid} = Session.start(workflow_id) |> Session.ready?()
      %Session{shared_doc_pid: shared_doc_pid} = :sys.get_state(pid)

      Session.stop(pid)

      # SharedDoc should still be alive if we want to control cleanup

      refute_eventually(Process.alive?(shared_doc_pid))

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
end
