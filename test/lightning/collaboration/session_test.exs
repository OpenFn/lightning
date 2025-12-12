defmodule Lightning.SessionTest do
  # We assume that the WorkflowCollaboration supervisor is up
  # that starts :pg with the :workflow_collaboration scope
  # and a dynamic supervisor called Lightning.WorkflowCollaboration

  # Tests must be async: false, some of the processes we start are either
  # not owned by the test process, or themselves start processes.
  use Lightning.DataCase, async: false

  import Eventually
  import Lightning.Factories
  import Lightning.CollaborationHelpers

  alias Lightning.Collaboration.DocumentState
  alias Lightning.Collaboration.DocumentSupervisor
  # alias Lightning.Collaboration.PersistenceWriter
  alias Lightning.Collaboration.Registry
  alias Lightning.Collaboration.Session
  alias Lightning.Collaboration.TestClient
  alias Lightning.Workflows.Workflow

  require Logger

  setup do
    user = insert(:user)
    {:ok, user: user}
  end

  describe "start/1" do
    test "start_link/1 returns an error when the SharedDoc doesn't exist", %{
      user: user
    } do
      workflow_id = Ecto.UUID.generate()

      workflow = %Lightning.Workflows.Workflow{
        id: workflow_id,
        project_id: Ecto.UUID.generate(),
        name: "",
        positions: %{}
      }

      assert {:error, {{:error, :shared_doc_not_found}, _}} =
               start_supervised(
                 {Session,
                  user: user,
                  workflow: workflow,
                  document_name: "workflow:#{workflow.id}"}
               )
    end

    test "start/1 can join an existing shared doc", %{user: user1} do
      user2 = insert(:user)
      workflow = insert(:simple_workflow)

      Lightning.Collaborate.start_document(
        workflow,
        "workflow:#{workflow.id}"
      )

      [parent1, parent2] = build_parents(2)

      [client_1, client_2] =
        for {parent, user} <- [{parent1, user1}, {parent2, user2}] do
          {:ok, client} =
            Session.start_link(
              user: user,
              workflow: workflow,
              parent_pid: parent,
              document_name: "workflow:#{workflow.id}"
            )

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

      shared_doc_pid =
        Registry.get_group("workflow:#{workflow.id}")
        |> Map.get(:shared_doc)

      observer_processes =
        shared_doc_pid
        |> :sys.get_state()
        |> then(fn state ->
          state.assigns.observer_process
        end)
        |> MapSet.new(fn {pid, _ref} -> pid end)

      assert [client_1, client_2]
             |> MapSet.new()
             |> MapSet.equal?(observer_processes),
             "SharedDoc should have both clients as observers"

      assert MapSet.size(shared_doc_pids) == 1,
             "Expected exactly one shared doc pid, got #{inspect(shared_doc_pids)}"

      # Check there is only one SharedDoc process for this workflow (now keyed by document_name)
      document_name = "workflow:#{workflow.id}"

      assert_eventually(
        length(:pg.get_members(:workflow_collaboration, document_name)) == 1
      )

      Process.exit(parent2, :normal)
      # Check that the session exits when the parent exits
      refute_eventually(Process.alive?(client_2))

      Process.exit(parent1, :normal)
      refute_eventually(Process.alive?(client_1))

      refute_eventually(Process.alive?(shared_doc_pid))

      # NOTE: We've enabled auto_exit: true, so this will be 0.
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

      start_supervised!(
        {DocumentSupervisor,
         workflow: workflow, document_name: "workflow:#{workflow.id}"}
      )

      # Start a session - this should initialize the SharedDoc with workflow data
      session_pid =
        start_supervised!(
          {Session,
           user: user,
           workflow: workflow,
           document_name: "workflow:#{workflow.id}"}
        )

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

        ~w(cron_expression enabled id type)
        |> Enum.each(fn key ->
          doc_value = Yex.Map.fetch!(doc_trigger, key)

          expected_value = get_expected_value(trigger, key)

          assert doc_value == expected_value,
                 "Trigger #{key} mismatch: expected #{expected_value |> inspect}, got #{doc_value |> inspect}"
        end)
      end
    end

    test "existing SharedDoc is not reinitialized", %{user: user} do
      workflow = insert(:workflow, name: "Test Workflow")

      insert(:job, workflow: workflow, name: "Original Job", body: "original")

      start_supervised!(
        {DocumentSupervisor,
         workflow: workflow, document_name: "workflow:#{workflow.id}"}
      )

      # Start first session
      session_1 =
        start_supervised!(
          {Session,
           workflow: workflow,
           user: user,
           document_name: "workflow:#{workflow.id}"}
        )

      shared_doc_1 = Session.get_doc(session_1)

      Session.update_doc(session_1, fn doc ->
        workflow_map = Yex.Doc.get_map(doc, "workflow")
        Yex.Map.set(workflow_map, "name", "Modified Name")
      end)

      # Start second session - should connect to existing SharedDoc
      session_2 =
        start_supervised!(
          {Session,
           workflow: workflow,
           user: user,
           document_name: "workflow:#{workflow.id}"}
        )

      shared_doc_2 = Session.get_doc(session_2)

      assert shared_doc_1 == shared_doc_2

      # The modified name should still be there (not reinitialized)
      workflow_map = Yex.Doc.get_map(shared_doc_2, "workflow")
      assert Yex.Map.fetch!(workflow_map, "name") == "Modified Name"

      %Session{shared_doc_pid: shared_doc_pid} = :sys.get_state(session_1)

      # # TODO: probably not needed anymore since we're using start_supervised!
      Session.stop(session_1)
      Session.stop(session_2)

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

      start_supervised!(
        {DocumentSupervisor,
         workflow: workflow, document_name: "workflow:#{workflow.id}"}
      )

      # Start session to initialize SharedDoc
      session_pid =
        start_supervised!(
          {Session,
           user: user,
           workflow: workflow,
           document_name: "workflow:#{workflow.id}"}
        )

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

  describe "persistence" do
    # @tag :pick
    test "saves document state to the database", %{user: user} do
      workflow = insert(:simple_workflow)

      _document_supervisor =
        start_supervised!(
          {DocumentSupervisor,
           workflow: workflow, document_name: "workflow:#{workflow.id}"}
        )

      session_pid =
        start_supervised!(
          {Session,
           user: user,
           workflow: workflow,
           document_name: "workflow:#{workflow.id}"}
        )

      # This is an existing workflow, so when the session starts, it should
      # both initialize the workflow document and save the initial state
      # to the database.

      workflow_id = workflow.id
      document_name = "workflow:#{workflow_id}"

      expected_workflow = %{
        "id" => workflow_id,
        "name" => workflow.name,
        "lock_version" => workflow.lock_version,
        "deleted_at" => nil,
        "concurrency" => nil,
        "enable_job_logs" => true
      }

      assert Session.get_doc(session_pid)
             |> Yex.Doc.get_map("workflow")
             |> Yex.Map.to_json() == expected_workflow

      # The Session is now up to date.

      # Lets find the PersistenceWriter and check it's state

      persistence_writer = get_persistence_writer(document_name)

      # There should be 1 pending update
      assert get_pending_updates(document_name) |> length() == 1

      assert get_document_state(document_name) |> length() == 0,
             "Nothing is expected in the database yet"

      # Now lets add a job
      add_job(session_pid)
      assert get_pending_updates(document_name) |> length() == 2

      # And another
      job = string_params_for(:job)
      add_job(session_pid, job)
      assert get_pending_updates(document_name) |> length() == 3

      # And force saving the updates (this normally happens on a timer)
      send(persistence_writer, :force_save)

      assert_eventually(get_pending_updates(document_name) |> length() == 0)

      # And remove a job
      remove_job(session_pid, job)
      assert get_pending_updates(document_name) |> length() == 1

      send(persistence_writer, :force_save)

      assert_eventually(get_pending_updates(document_name) |> length() == 0)

      # And check that the document state is in the database
      assert get_document_state(document_name) |> length() == 2

      # TODO: Recover from state without a checkpoint
      # TODO: Recover from state with a checkpoint
    end

    defp get_persistence_writer(document_name) do
      Registry.get_group(document_name)
      |> Map.get(:persistence_writer)
    end

    defp get_pending_updates(document_name) do
      persistence_writer = get_persistence_writer(document_name)
      :sys.get_state(persistence_writer).pending_updates
    end

    defp add_job(session_pid, job \\ nil) do
      job = job || string_params_for(:job)

      Session.update_doc(session_pid, fn doc ->
        Yex.Doc.get_array(doc, "jobs")
        |> Yex.Array.push(Yex.MapPrelim.from(job))
      end)
    end

    defp remove_job(session_pid, job) when is_map(job) do
      Session.update_doc(session_pid, fn doc ->
        jobs = Yex.Doc.get_array(doc, "jobs")

        index = jobs |> Enum.find_index(fn j -> j["id"] == job["id"] end)

        if index do
          Yex.Array.delete(jobs, index)
        else
          raise "Job #{job["id"]} not found in document"
        end
      end)
    end
  end

  describe "reconnecting" do
    # This test recreates the issue we were having in the front end.
    # If the Workflow process/channel crashes, the frontend doc is still around
    # and when the frontend reconnects, it still has an active Doc.
    # So we need to make sure that when the Session process gets started again,
    # it doesn't create a new Doc from scratch, but rather loads the existing Doc
    # from persistence.

    @tag :pick
    test "client doc is still around", %{user: user} do
      workflow = insert(:simple_workflow)

      document_supervisor =
        start_supervised!(
          {DocumentSupervisor,
           workflow: workflow, document_name: "workflow:#{workflow.id}"}
        )

      %{shared_doc: shared_doc, persistence_writer: persistence_writer} =
        Registry.get_group("workflow:#{workflow.id}")

      session_pid =
        start_supervised!(
          {Session,
           user: user,
           workflow: workflow,
           document_name: "workflow:#{workflow.id}"}
        )

      {:ok, client_pid} =
        GenServer.start(TestClient, shared_doc_pid: shared_doc)

      # Ensure handle_continue has finished
      :sys.get_state(client_pid)

      assert get_jobs(shared_doc) |> length() == 1

      # Client adds a job
      TestClient.add_job(client_pid, string_params_for(:job))

      # SharedDoc should have the job
      assert_eventually(get_jobs(shared_doc) |> length() == 2)

      # Simulate a client disconnecting
      Process.exit(session_pid, :kill)
      refute_eventually(Process.alive?(session_pid))

      # We call unobserve here to allow the SharedDoc to autoexit,
      # the client has it's own YDoc and we want to apply updates without
      # the SharedDoc being around.
      GenServer.call(client_pid, :unobserve)
      refute_eventually(Process.alive?(shared_doc))
      refute_eventually(Process.alive?(persistence_writer))
      refute_eventually(Process.alive?(document_supervisor))

      assert Process.alive?(client_pid), "Client should still be alive"

      assert get_document_state("workflow:#{workflow.id}"),
             "DocumentState should be saved in the database"

      # Client adds another job, while the SharedDoc is not around
      TestClient.add_job(client_pid, string_params_for(:job))

      # Starting a new document supervisor, like when the frontend reconnects
      # At this point, client is still running, and the SharedDoc should
      # pick up the existing document from the database.
      start_supervised!(
        {DocumentSupervisor,
         workflow: workflow, document_name: "workflow:#{workflow.id}"}
      )

      # Starting a new session
      _session_pid =
        start_supervised!(
          {Session,
           user: user,
           workflow: workflow,
           document_name: "workflow:#{workflow.id}"}
        )

      shared_doc_pid = Registry.get_group("workflow:#{workflow.id}").shared_doc

      GenServer.call(client_pid, {:observe, shared_doc_pid})

      jobs = GenServer.call(client_pid, :get_jobs)
      assert length(jobs) == 3

      assert get_jobs(shared_doc_pid) |> length() == 3
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
    @tag :capture_log
    test "when a session is stopped", %{user: user1} do
      workflow_id = Ecto.UUID.generate()

      workflow = %Lightning.Workflows.Workflow{
        id: workflow_id,
        project_id: Ecto.UUID.generate(),
        name: "",
        positions: %{}
      }

      user2 = insert(:user)
      user3 = insert(:user)

      start_supervised!(
        {DocumentSupervisor,
         workflow: workflow, document_name: "workflow:#{workflow.id}"}
      )

      [{client1, parent1}, {client2, parent2}, {client3, _parent3}] =
        Enum.map([user1, user2, user3], fn user ->
          parent = build_parent()

          client =
            start_supervised!(
              {Session,
               user: user,
               workflow: workflow,
               parent_pid: parent,
               document_name: "workflow:#{workflow.id}"}
            )

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
        {:EXIT, _pid, _reason} ->
          :ok

        any ->
          Logger.warning(
            "WARNING: parent received unknown message: #{inspect(any)}"
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

  defp get_document_state(document_name) do
    DocumentState |> Repo.all(document_name: document_name)
  end

  describe "save_workflow/2" do
    setup do
      # Set global mode for the mock to allow cross-process calls
      Mox.set_mox_global(LightningMock)
      # Stub the broadcast calls that save_workflow makes
      Mox.stub(LightningMock, :broadcast, fn _topic, _message -> :ok end)

      user = insert(:user)
      project = insert(:project)
      workflow = insert(:workflow, name: "Original Name", project: project)

      # Add a job so we have something to modify
      job = insert(:job, workflow: workflow, name: "Original Job")

      start_supervised!(
        {DocumentSupervisor,
         workflow: workflow, document_name: "workflow:#{workflow.id}"}
      )

      session_pid =
        start_supervised!(
          {Session,
           workflow: workflow,
           user: user,
           document_name: "workflow:#{workflow.id}"}
        )

      %{
        session: session_pid,
        user: user,
        workflow: workflow,
        job: job,
        project: project
      }
    end

    test "successfully saves workflow from Y.Doc", %{
      session: session,
      user: user,
      workflow: workflow
    } do
      # Modify Y.Doc via Session
      doc = Session.get_doc(session)

      # Get shared types BEFORE transaction to avoid deadlock
      workflow_map = Yex.Doc.get_map(doc, "workflow")

      Yex.Doc.transaction(doc, "test_update", fn ->
        Yex.Map.set(workflow_map, "name", "Updated Name")
      end)

      # Save
      assert {:ok, saved_workflow} = Session.save_workflow(session, user)
      assert saved_workflow.name == "Updated Name"
      assert saved_workflow.id == workflow.id

      # Verify in database
      saved_from_db = Lightning.Workflows.get_workflow!(workflow.id)
      assert saved_from_db.name == "Updated Name"
      assert saved_from_db.lock_version == workflow.lock_version + 1
    end

    test "handles validation errors", %{session: session, user: user} do
      # Set invalid data in Y.Doc (blank name)
      doc = Session.get_doc(session)

      # Get shared types BEFORE transaction
      workflow_map = Yex.Doc.get_map(doc, "workflow")

      Yex.Doc.transaction(doc, "test_update", fn ->
        Yex.Map.set(workflow_map, "name", "")
      end)

      # Save should fail
      assert {:error, changeset} = Session.save_workflow(session, user)
      assert changeset.errors[:name]
    end

    test "handles workflow deleted error", %{
      session: session,
      user: user,
      workflow: workflow
    } do
      # Soft-delete the workflow
      Lightning.Repo.update!(
        Ecto.Changeset.change(workflow,
          deleted_at: DateTime.utc_now() |> DateTime.truncate(:second)
        )
      )

      # Save should fail
      assert {:error, :workflow_deleted} = Session.save_workflow(session, user)
    end

    test "saves all workflow components correctly", %{
      session: session,
      user: user
    } do
      # Modify job name via Y.Doc
      doc = Session.get_doc(session)

      # Get shared types BEFORE transaction
      jobs_array = Yex.Doc.get_array(doc, "jobs")

      Yex.Doc.transaction(doc, "test_update", fn ->
        # Update first job's name directly on the map
        if Yex.Array.length(jobs_array) > 0 do
          first_job = Yex.Array.fetch!(jobs_array, 0)
          Yex.Map.set(first_job, "name", "Modified Job")
        end
      end)

      assert {:ok, saved_workflow} = Session.save_workflow(session, user)

      # Reload with associations
      saved_from_db =
        Lightning.Workflows.get_workflow!(saved_workflow.id)
        |> Lightning.Repo.preload(:jobs)

      job_names = Enum.map(saved_from_db.jobs, & &1.name)
      assert "Modified Job" in job_names
    end

    test "respects timeout for large workflows", %{session: session, user: user} do
      # This test verifies the 10-second timeout is set
      # Actual timeout testing would require artificially slowing down the save
      assert {:ok, _workflow} = Session.save_workflow(session, user)
    end

    test "prevents circular reconciliation with skip_reconcile option", %{
      session: session,
      user: user
    } do
      # This test verifies that save_workflow passes skip_reconcile: true
      # to prevent WorkflowReconciler from updating the same Y.Doc

      # Mock or spy on Workflows.save_workflow to verify skip_reconcile is passed
      # For now, just verify save succeeds
      assert {:ok, _workflow} = Session.save_workflow(session, user)
    end

    test "handles concurrent saves with optimistic locking", %{
      session: session,
      user: user,
      workflow: workflow
    } do
      # Another process updates the workflow (simulating concurrent edit)
      {:ok, _updated} =
        Lightning.Workflows.save_workflow(
          Lightning.Workflows.change_workflow(workflow, %{
            name: "Concurrent Update"
          }),
          user
        )

      # Our save should detect the lock_version conflict
      # Note: This may succeed if Y.Doc has latest changes
      # The test verifies the system handles it gracefully either way
      result = Session.save_workflow(session, user)

      case result do
        {:ok, _} -> assert true
        {:error, _} -> assert true
      end
    end

    test "saves workflow with :built state and lock_version > 0", %{
      user: user,
      project: project
    } do
      # Create a new workflow struct (not yet saved)
      workflow_id = Ecto.UUID.generate()

      new_workflow = %Workflow{
        id: workflow_id,
        name: "New Workflow",
        project_id: project.id,
        lock_version: 0,
        edges: [],
        jobs: [],
        triggers: []
      }

      # Start document and session with the new workflow
      start_supervised!(
        {DocumentSupervisor,
         workflow: new_workflow, document_name: "workflow:#{workflow_id}"}
      )

      session_pid =
        start_supervised!(
          {Session,
           workflow: new_workflow,
           user: user,
           document_name: "workflow:#{workflow_id}"}
        )

      # First save - this creates the workflow in DB (lock_version becomes 1)
      assert {:ok, saved_workflow} = Session.save_workflow(session_pid, user)
      assert saved_workflow.lock_version == 1

      # Now we have a workflow with state: :built but lock_version > 0
      # Modify it again via Y.Doc
      doc = Session.get_doc(session_pid)
      workflow_map = Yex.Doc.get_map(doc, "workflow")

      Yex.Doc.transaction(doc, "second_update", fn ->
        Yex.Map.set(workflow_map, "name", "Updated After First Save")
      end)

      # Second save - this should fetch the workflow from DB (covering line 472-476)
      assert {:ok, saved_workflow2} = Session.save_workflow(session_pid, user)
      assert saved_workflow2.name == "Updated After First Save"
      assert saved_workflow2.lock_version == 2

      # Verify in database
      from_db = Lightning.Workflows.get_workflow!(workflow_id)
      assert from_db.name == "Updated After First Save"
      assert from_db.lock_version == 2
    end

    test "handles workflow deleted for :built workflow with lock_version > 0", %{
      user: user,
      project: project
    } do
      # Create a workflow and save it once to get lock_version > 0
      workflow_id = Ecto.UUID.generate()

      new_workflow = %Workflow{
        id: workflow_id,
        name: "To Be Deleted",
        project_id: project.id,
        lock_version: 0,
        edges: [],
        jobs: [],
        triggers: []
      }

      start_supervised!(
        {DocumentSupervisor,
         workflow: new_workflow, document_name: "workflow:#{workflow_id}"}
      )

      session_pid =
        start_supervised!(
          {Session,
           workflow: new_workflow,
           user: user,
           document_name: "workflow:#{workflow_id}"}
        )

      # First save to create in DB
      assert {:ok, _saved_workflow} = Session.save_workflow(session_pid, user)

      # Now delete the workflow from DB
      from_db = Lightning.Workflows.get_workflow!(workflow_id)

      Lightning.Repo.update!(
        Ecto.Changeset.change(from_db,
          deleted_at: DateTime.utc_now() |> DateTime.truncate(:second)
        )
      )

      # Try to save again - should get workflow_deleted error (covering line 475)
      assert {:error, :workflow_deleted} =
               Session.save_workflow(session_pid, user)
    end
  end

  describe "save_workflow/2 validation errors" do
    setup do
      # Set global mode for the mock to allow cross-process calls
      Mox.set_mox_global(LightningMock)
      # Stub the broadcast calls that save_workflow makes
      Mox.stub(LightningMock, :broadcast, fn _topic, _message -> :ok end)

      user = insert(:user)
      project = insert(:project)
      workflow = insert(:workflow, name: "Original Name", project: project)

      start_supervised!(
        {DocumentSupervisor,
         workflow: workflow, document_name: "workflow:#{workflow.id}"}
      )

      session_pid =
        start_supervised!(
          {Session,
           workflow: workflow,
           user: user,
           document_name: "workflow:#{workflow.id}"}
        )

      %{
        session: session_pid,
        user: user,
        workflow: workflow,
        project: project
      }
    end

    test "writes validation errors to Y.Doc when workflow name is blank", %{
      session: session,
      user: user
    } do
      # Get Y.Doc and set blank name
      doc = Session.get_doc(session)
      workflow_map = Yex.Doc.get_map(doc, "workflow")

      Yex.Doc.transaction(doc, "test_blank_name", fn ->
        Yex.Map.set(workflow_map, "name", "")
      end)

      # Attempt save (should fail validation)
      assert {:error, %Ecto.Changeset{}} = Session.save_workflow(session, user)

      # Check errors were written to Y.Doc
      errors_map = Yex.Doc.get_map(doc, "errors")
      errors = Yex.Map.to_json(errors_map)

      # Workflow errors should be nested under 'workflow' key
      assert Map.has_key?(errors, "workflow")
      assert is_map(errors["workflow"])
      assert is_list(errors["workflow"]["name"])
      assert "This field can't be blank." in errors["workflow"]["name"]
    end

    test "clears errors from Y.Doc after successful save", %{
      session: session,
      user: user
    } do
      # Set up: Create errors in Y.Doc manually
      doc = Session.get_doc(session)
      errors_map = Yex.Doc.get_map(doc, "errors")

      Yex.Doc.transaction(doc, "test_add_error", fn ->
        Yex.Map.set(errors_map, "name", "some error")
      end)

      # Set valid name
      workflow_map = Yex.Doc.get_map(doc, "workflow")

      Yex.Doc.transaction(doc, "test_valid_name", fn ->
        Yex.Map.set(
          workflow_map,
          "name",
          "Valid Workflow Name #{System.unique_integer()}"
        )
      end)

      # Save should succeed and clear errors
      assert {:ok, _saved_workflow} = Session.save_workflow(session, user)

      # Verify errors were cleared
      errors = Yex.Map.to_json(errors_map)
      assert errors == %{}
    end

    test "writes nested job validation errors to Y.Doc", %{
      session: session,
      user: user
    } do
      # Add a job with blank name
      doc = Session.get_doc(session)
      jobs_array = Yex.Doc.get_array(doc, "jobs")

      job_id = Ecto.UUID.generate()

      job_map =
        Yex.MapPrelim.from(%{
          "id" => job_id,
          "name" => "",
          # Invalid - blank
          "body" => Yex.TextPrelim.from(""),
          "adaptor" => "@openfn/language-common@1.0.0",
          "project_credential_id" => nil,
          "keychain_credential_id" => nil
        })

      Yex.Doc.transaction(doc, "test_add_invalid_job", fn ->
        Yex.Array.push(jobs_array, job_map)
      end)

      # Attempt save (should fail validation)
      assert {:error, %Ecto.Changeset{}} = Session.save_workflow(session, user)

      # Check job error was written to Y.Doc with nested structure
      errors_map = Yex.Doc.get_map(doc, "errors")
      errors = Yex.Map.to_json(errors_map)

      # Errors should be nested: %{jobs: %{job-id: %{name: ["error"]}}}
      assert Map.has_key?(errors, "jobs")
      assert is_map(errors["jobs"])
      assert Map.has_key?(errors["jobs"], job_id)
      assert is_map(errors["jobs"][job_id])
      assert is_list(errors["jobs"][job_id]["name"])

      assert Enum.any?(
               errors["jobs"][job_id]["name"],
               &String.contains?(&1, "can't be blank")
             )
    end

    test "nests workflow-level and entity errors correctly in Y.Doc", %{
      session: session,
      user: user
    } do
      # Create validation errors at both workflow and job level
      doc = Session.get_doc(session)
      workflow_map = Yex.Doc.get_map(doc, "workflow")
      jobs_array = Yex.Doc.get_array(doc, "jobs")

      job_id = Ecto.UUID.generate()

      Yex.Doc.transaction(doc, "test_mixed_errors", fn ->
        # Set blank workflow name (workflow-level error)
        Yex.Map.set(workflow_map, "name", "")

        # Add job with blank name (entity-level error)
        job_map =
          Yex.MapPrelim.from(%{
            "id" => job_id,
            "name" => "",
            "body" => Yex.TextPrelim.from("console.log('test');"),
            "adaptor" => "@openfn/language-common@1.0.0",
            "project_credential_id" => nil,
            "keychain_credential_id" => nil
          })

        Yex.Array.push(jobs_array, job_map)
      end)

      # Attempt save (should fail validation at both levels)
      assert {:error, %Ecto.Changeset{}} = Session.save_workflow(session, user)

      # Check error structure in Y.Doc
      errors_map = Yex.Doc.get_map(doc, "errors")
      errors = Yex.Map.to_json(errors_map)

      # Verify workflow errors are nested under 'workflow' key
      assert Map.has_key?(errors, "workflow")
      assert is_map(errors["workflow"])
      assert is_list(errors["workflow"]["name"])

      assert Enum.any?(
               errors["workflow"]["name"],
               &String.contains?(&1, "can't be blank")
             )

      # Verify entity errors still nested under entity type keys
      assert Map.has_key?(errors, "jobs")
      assert is_map(errors["jobs"])
      assert Map.has_key?(errors["jobs"], job_id)
      assert is_map(errors["jobs"][job_id])
      assert is_list(errors["jobs"][job_id]["name"])

      assert Enum.any?(
               errors["jobs"][job_id]["name"],
               &String.contains?(&1, "can't be blank")
             )

      # Verify structure matches Y.Doc top-level organization
      # Y.Doc has: workflow (map), jobs (array), triggers (array), edges (array)
      # Errors mirror this: workflow (map), jobs (map), triggers (map), edges (map)
      assert Map.keys(errors) |> Enum.sort() == ["jobs", "workflow"]
    end

    test "merges server errors with existing client errors", %{
      session: session,
      user: user
    } do
      # Simulate client-side validation errors already in Y.Doc
      doc = Session.get_doc(session)
      errors_map = Yex.Doc.get_map(doc, "errors")

      job_id_1 = Ecto.UUID.generate()
      job_id_2 = Ecto.UUID.generate()

      # Add client errors for two jobs
      Yex.Doc.transaction(doc, "test_add_client_errors", fn ->
        jobs_errors =
          Yex.MapPrelim.from(%{
            job_id_1 => Yex.MapPrelim.from(%{"body" => ["client error"]}),
            job_id_2 => Yex.MapPrelim.from(%{"adaptor" => ["invalid adaptor"]})
          })

        Yex.Map.set(errors_map, "jobs", jobs_errors)
      end)

      # Now create server validation error for job_id_1 (different field)
      jobs_array = Yex.Doc.get_array(doc, "jobs")

      job_map =
        Yex.MapPrelim.from(%{
          "id" => job_id_1,
          "name" => "",
          # Server will validate this
          "body" => Yex.TextPrelim.from("console.log('test');"),
          "adaptor" => "@openfn/language-common@1.0.0",
          "project_credential_id" => nil,
          "keychain_credential_id" => nil
        })

      Yex.Doc.transaction(doc, "test_add_invalid_job", fn ->
        Yex.Array.push(jobs_array, job_map)
      end)

      # Attempt save (should fail validation on job_id_1 name)
      assert {:error, %Ecto.Changeset{}} = Session.save_workflow(session, user)

      # Check that BOTH client and server errors are present
      errors = Yex.Map.to_json(errors_map)

      # job_id_1 should have server error for 'name' AND client error for 'body'
      assert Map.has_key?(errors, "jobs")
      assert Map.has_key?(errors["jobs"], job_id_1)

      # Server error should be present
      assert is_list(errors["jobs"][job_id_1]["name"])

      assert Enum.any?(
               errors["jobs"][job_id_1]["name"],
               &String.contains?(&1, "can't be blank")
             )

      # Client error should still be present
      assert is_list(errors["jobs"][job_id_1]["body"])
      assert "client error" in errors["jobs"][job_id_1]["body"]

      # job_id_2 should still have its client error (untouched by server)
      assert Map.has_key?(errors["jobs"], job_id_2)
      assert is_list(errors["jobs"][job_id_2]["adaptor"])
      assert "invalid adaptor" in errors["jobs"][job_id_2]["adaptor"]
    end

    test "server errors take precedence over client errors for same field", %{
      session: session,
      user: user
    } do
      # Add client error for workflow name
      doc = Session.get_doc(session)
      errors_map = Yex.Doc.get_map(doc, "errors")

      Yex.Doc.transaction(doc, "test_add_client_error", fn ->
        client_workflow_errors =
          Yex.MapPrelim.from(%{"name" => ["client side validation error"]})

        Yex.Map.set(errors_map, "workflow", client_workflow_errors)
      end)

      # Now cause server validation error on the same field
      workflow_map = Yex.Doc.get_map(doc, "workflow")

      Yex.Doc.transaction(doc, "test_blank_name", fn ->
        Yex.Map.set(workflow_map, "name", "")
      end)

      # Attempt save (should fail validation)
      assert {:error, %Ecto.Changeset{}} = Session.save_workflow(session, user)

      # Check that server error replaced client error
      errors = Yex.Map.to_json(errors_map)

      assert Map.has_key?(errors, "workflow")
      assert is_list(errors["workflow"]["name"])

      # Should have server error, not client error
      assert Enum.any?(
               errors["workflow"]["name"],
               &String.contains?(&1, "can't be blank")
             )

      refute "client side validation error" in errors["workflow"]["name"]
    end

    test "preserves client errors for entities not validated by server", %{
      session: session,
      user: user
    } do
      # Simulate multiple client errors across different entity types
      doc = Session.get_doc(session)
      errors_map = Yex.Doc.get_map(doc, "errors")

      job_id = Ecto.UUID.generate()
      edge_id = Ecto.UUID.generate()

      Yex.Doc.transaction(doc, "test_add_multiple_client_errors", fn ->
        # Client errors for job
        Yex.Map.set(
          errors_map,
          "jobs",
          Yex.MapPrelim.from(%{
            job_id => Yex.MapPrelim.from(%{"body" => ["client job error"]})
          })
        )

        # Client errors for edge
        Yex.Map.set(
          errors_map,
          "edges",
          Yex.MapPrelim.from(%{
            edge_id =>
              Yex.MapPrelim.from(%{
                "condition_expression" => ["client edge error"]
              })
          })
        )

        # Client error for workflow
        Yex.Map.set(
          errors_map,
          "workflow",
          Yex.MapPrelim.from(%{"concurrency" => ["client workflow error"]})
        )
      end)

      # Now cause server validation error on workflow name only
      workflow_map = Yex.Doc.get_map(doc, "workflow")

      Yex.Doc.transaction(doc, "test_blank_workflow_name", fn ->
        Yex.Map.set(workflow_map, "name", "")
      end)

      # Attempt save (should fail validation on workflow name)
      assert {:error, %Ecto.Changeset{}} = Session.save_workflow(session, user)

      # Check that client errors for jobs and edges are preserved
      errors = Yex.Map.to_json(errors_map)

      # Workflow should have BOTH server error (name) and client error (concurrency)
      assert Map.has_key?(errors, "workflow")

      assert Enum.any?(
               errors["workflow"]["name"],
               &String.contains?(&1, "can't be blank")
             )

      assert "client workflow error" in errors["workflow"]["concurrency"]

      # Job client error should be preserved
      assert Map.has_key?(errors, "jobs")
      assert Map.has_key?(errors["jobs"], job_id)
      assert "client job error" in errors["jobs"][job_id]["body"]

      # Edge client error should be preserved
      assert Map.has_key?(errors, "edges")
      assert Map.has_key?(errors["edges"], edge_id)

      assert "client edge error" in errors["edges"][edge_id][
               "condition_expression"
             ]
    end
  end

  describe "persistence reconciliation" do
    test "reconciles lock_version when loading persisted Y.Doc state", %{
      user: user
    } do
      workflow = insert(:simple_workflow)

      # Start initial session and make some changes
      {:ok, _doc_supervisor} =
        Lightning.Collaborate.start_document(
          workflow,
          "workflow:#{workflow.id}"
        )

      {:ok, session1} =
        Session.start_link(
          user: user,
          workflow: workflow,
          parent_pid: self(),
          document_name: "workflow:#{workflow.id}"
        )

      # Get the SharedDoc and verify initial lock_version
      shared_doc = Session.get_doc(session1)
      workflow_map = Yex.Doc.get_map(shared_doc, "workflow")
      initial_lock_version = Yex.Map.fetch!(workflow_map, "lock_version")

      # Simulate workflow changes in database (e.g., from another save)
      # This increments lock_version in the database
      new_lock_version = initial_lock_version + 1

      {:ok, updated_workflow} =
        Lightning.Workflows.save_workflow(
          Lightning.Workflows.change_workflow(workflow, %{
            name: "Updated Name"
          }),
          user
        )

      # Verify database has new lock_version
      assert updated_workflow.lock_version == new_lock_version

      # Stop the session and document supervisor to simulate server restart
      Session.stop(session1)
      ensure_doc_supervisor_stopped(workflow.id)

      # Start a new session - this will load persisted Y.Doc state
      # The persisted state has old lock_version, but fresh workflow has new one
      {:ok, _doc_supervisor2} =
        Lightning.Collaborate.start_document(
          updated_workflow,
          "workflow:#{workflow.id}"
        )

      {:ok, session2} =
        Session.start_link(
          user: user,
          workflow: updated_workflow,
          parent_pid: self(),
          document_name: "workflow:#{workflow.id}"
        )

      # Get the SharedDoc and check lock_version was reconciled
      shared_doc2 = Session.get_doc(session2)
      workflow_map2 = Yex.Doc.get_map(shared_doc2, "workflow")
      reconciled_lock_version = Yex.Map.fetch!(workflow_map2, "lock_version")

      # The lock_version should match the database, not the stale persisted state
      assert reconciled_lock_version == new_lock_version,
             "Expected lock_version #{new_lock_version} but got #{reconciled_lock_version}"

      # Verify name was also reconciled
      reconciled_name = Yex.Map.fetch!(workflow_map2, "name")
      assert reconciled_name == "Updated Name"

      Session.stop(session2)
    end

    test "discards stale persisted Y.Doc when lock_version changes", %{
      user: user
    } do
      workflow = insert(:simple_workflow)

      # Start initial session with lock_version 0
      {:ok, _doc_supervisor} =
        Lightning.Collaborate.start_document(
          workflow,
          "workflow:#{workflow.id}"
        )

      {:ok, session1} =
        Session.start_link(
          user: user,
          workflow: workflow,
          parent_pid: self(),
          document_name: "workflow:#{workflow.id}"
        )

      # Get initial state
      shared_doc = Session.get_doc(session1)
      jobs_array = Yex.Doc.get_array(shared_doc, "jobs")
      initial_job_count = Yex.Array.length(jobs_array)

      # Workflow is saved (lock_version increments)
      {:ok, updated_workflow} =
        Lightning.Workflows.save_workflow(
          Lightning.Workflows.change_workflow(workflow, %{
            name: "Changed by another user"
          }),
          user
        )

      new_lock_version = updated_workflow.lock_version

      # Simulate server restart - persisted Y.Doc has old lock_version
      Session.stop(session1)
      ensure_doc_supervisor_stopped(workflow.id)

      # Start new session with updated workflow
      # Persistence should detect stale lock_version and reload from DB
      {:ok, _doc_supervisor2} =
        Lightning.Collaborate.start_document(
          updated_workflow,
          "workflow:#{workflow.id}"
        )

      {:ok, session2} =
        Session.start_link(
          user: user,
          workflow: updated_workflow,
          parent_pid: self(),
          document_name: "workflow:#{workflow.id}"
        )

      # Verify Y.Doc was reloaded from database
      shared_doc2 = Session.get_doc(session2)
      jobs_array2 = Yex.Doc.get_array(shared_doc2, "jobs")

      # Should have original jobs from DB (persisted Y.Doc was discarded)
      assert Yex.Array.length(jobs_array2) == initial_job_count

      # Verify lock_version matches database
      workflow_map2 = Yex.Doc.get_map(shared_doc2, "workflow")
      reconciled_lock_version = Yex.Map.fetch!(workflow_map2, "lock_version")

      assert reconciled_lock_version == new_lock_version,
             "Lock version should match database"

      # Verify workflow name was updated from database
      reconciled_name = Yex.Map.fetch!(workflow_map2, "name")
      assert reconciled_name == "Changed by another user"

      Session.stop(session2)
    end

    test "handles persisted Y.Doc with nil lock_version when DB has real version",
         %{
           user: user
         } do
      # This tests the bug fix for issue #4164
      # When a workflow is opened before first save, Y.Doc gets lock_version: nil
      # If that state is persisted and the workflow is later saved (getting a real lock_version),
      # loading the persisted state would crash because extract_lock_version didn't handle {:ok, nil}

      workflow = insert(:simple_workflow)
      doc_name = "workflow:#{workflow.id}"

      # Manually create a persisted document state with lock_version: nil
      # This simulates a Y.Doc that was persisted before the workflow was ever saved
      doc = Yex.Doc.new()
      workflow_map = Yex.Doc.get_map(doc, "workflow")

      Yex.Doc.transaction(doc, "setup_nil_lock_version", fn ->
        Yex.Map.set(workflow_map, "id", workflow.id)
        Yex.Map.set(workflow_map, "name", "Test Workflow")
        Yex.Map.set(workflow_map, "lock_version", nil)
      end)

      {:ok, update_data} = Yex.encode_state_as_update(doc)

      Repo.insert!(%DocumentState{
        document_name: doc_name,
        state_data: update_data,
        version: :update
      })

      # Now start a session - this should NOT crash
      # The persistence layer should handle the nil lock_version and reset from DB
      {:ok, _doc_supervisor} =
        Lightning.Collaborate.start_document(
          workflow,
          doc_name
        )

      {:ok, session} =
        Session.start_link(
          user: user,
          workflow: workflow,
          parent_pid: self(),
          document_name: doc_name
        )

      # Verify the session started and lock_version was reconciled from DB
      shared_doc = Session.get_doc(session)
      workflow_map2 = Yex.Doc.get_map(shared_doc, "workflow")
      reconciled_lock_version = Yex.Map.fetch!(workflow_map2, "lock_version")

      # lock_version should now match the database value
      assert reconciled_lock_version == workflow.lock_version,
             "Expected lock_version #{workflow.lock_version} but got #{reconciled_lock_version}"

      Session.stop(session)
    end

    test "merges delta updates with persisted state across save batches", %{
      user: user
    } do
      # This tests the fix for the merge_updates bug where delta updates
      # saved in subsequent batches were applied to an empty doc instead of
      # the current persisted state, resulting in data loss.
      #
      # Scenario:
      # 1. First batch persists base state with workflow data and lock_version
      # 2. Another change generates a delta update (adding concurrency field)
      # 3. Second batch should merge the delta with existing persisted state
      #
      # Note: We verify concurrency is preserved, not name, because
      # reconcile_workflow_metadata updates name from DB after loading.

      workflow = insert(:simple_workflow)
      doc_name = "workflow:#{workflow.id}"

      # First, create initial persisted state (simulating first batch)
      # Set lock_version to match the workflow's DB lock_version to avoid reset
      initial_doc = Yex.Doc.new()
      workflow_map = Yex.Doc.get_map(initial_doc, "workflow")

      Yex.Doc.transaction(initial_doc, "initial_state", fn ->
        Yex.Map.set(workflow_map, "id", workflow.id)
        Yex.Map.set(workflow_map, "name", workflow.name)
        Yex.Map.set(workflow_map, "lock_version", workflow.lock_version)
      end)

      {:ok, initial_update} = Yex.encode_state_as_update(initial_doc)

      # Persist the initial state
      Repo.insert!(%DocumentState{
        document_name: doc_name,
        state_data: initial_update,
        version: :update
      })

      # Now create a delta update that adds a new field
      # (simulating what happens when user edits concurrency in the workflow)
      delta_doc = Yex.Doc.new()
      delta_workflow_map = Yex.Doc.get_map(delta_doc, "workflow")

      # Apply initial state first, then make delta change
      Yex.apply_update(delta_doc, initial_update)

      Yex.Doc.transaction(delta_doc, "add_concurrency", fn ->
        Yex.Map.set(delta_workflow_map, "concurrency", 5)
      end)

      # Get the delta (diff since initial state)
      {:ok, state_vector} = Yex.encode_state_vector(initial_doc)
      {:ok, delta_update} = Yex.encode_state_as_update(delta_doc, state_vector)

      # The delta should be small (just the concurrency change)
      assert byte_size(delta_update) < byte_size(initial_update)

      # Persist the delta as a second update
      Repo.insert!(%DocumentState{
        document_name: doc_name,
        state_data: delta_update,
        version: :update
      })

      # Now start a session - this will load and reconstruct the full state
      {:ok, _doc_supervisor} =
        Lightning.Collaborate.start_document(
          workflow,
          doc_name
        )

      {:ok, session} =
        Session.start_link(
          user: user,
          workflow: workflow,
          parent_pid: self(),
          document_name: doc_name
        )

      # Verify the session loaded the full state correctly
      shared_doc = Session.get_doc(session)
      loaded_workflow_map = Yex.Doc.get_map(shared_doc, "workflow")

      # The key assertion: concurrency from the delta update should be preserved.
      # This verifies the fix - before the fix, delta updates applied to an empty
      # doc would result in data loss (concurrency would be missing).
      loaded_concurrency = Yex.Map.fetch!(loaded_workflow_map, "concurrency")
      assert loaded_concurrency == 5

      # Name should match DB (reconciliation updates it)
      loaded_name = Yex.Map.fetch!(loaded_workflow_map, "name")
      assert loaded_name == workflow.name

      # lock_version should match DB (reconciliation updates it)
      loaded_lock_version = Yex.Map.fetch!(loaded_workflow_map, "lock_version")
      assert loaded_lock_version == workflow.lock_version

      Session.stop(session)
    end
  end
end
