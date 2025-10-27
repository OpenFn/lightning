defmodule Lightning.Collaboration.DocumentSupervisorTest do
  use Lightning.DataCase, async: false

  alias Lightning.Collaboration.DocumentSupervisor
  alias Lightning.Collaboration.Registry

  import Eventually
  import Lightning.Factories
  import ExUnit.CaptureLog

  # Common setup for most tests
  setup do
    Process.flag(:trap_exit, true)
    workflow = insert(:workflow)
    workflow_id = workflow.id
    document_name = "workflow:#{workflow_id}"

    {:ok,
     workflow: workflow, workflow_id: workflow_id, document_name: document_name}
  end

  # Setup for tests that need a running DocumentSupervisor
  defp setup_document_supervisor(context) do
    {:ok, doc_supervisor} =
      DocumentSupervisor.start_link(
        [workflow: context.workflow, document_name: context.document_name],
        name: Registry.via({:doc_supervisor, context.document_name})
      )

    persistence_writer =
      Registry.whereis({:persistence_writer, context.document_name})

    shared_doc = Registry.whereis({:shared_doc, context.document_name})

    assert Process.alive?(doc_supervisor)
    assert Process.alive?(persistence_writer)
    assert Process.alive?(shared_doc)

    Map.merge(context, %{
      doc_supervisor: doc_supervisor,
      persistence_writer: persistence_writer,
      shared_doc: shared_doc
    })
  end

  # Setup for tests that need a test supervisor (like restart strategy test)
  defp setup_test_supervisor(context) do
    {:ok, test_supervisor} = DynamicSupervisor.start_link(strategy: :one_for_one)

    child_spec =
      DocumentSupervisor.child_spec(
        workflow: context.workflow,
        document_name: context.document_name,
        name: Registry.via({:doc_supervisor, context.document_name})
      )

    Map.merge(context, %{
      test_supervisor: test_supervisor,
      child_spec: child_spec
    })
  end

  # Helper function to verify cleanup after process termination
  defp verify_cleanup(document_name, _workflow_id) do
    # Verify Registry is cleaned up eventually
    refute_eventually(Registry.whereis({:doc_supervisor, document_name}))
    refute_eventually(Registry.whereis({:persistence_writer, document_name}))
    refute_eventually(Registry.whereis({:shared_doc, document_name}))

    # Verify process group is cleaned up eventually
    refute_eventually(
      :pg.get_members(:workflow_collaboration, document_name)
      |> Enum.any?()
    )
  end

  # Helper function to monitor processes and verify termination
  defp monitor_and_verify_termination(setup_data) do
    %{
      doc_supervisor: doc_supervisor,
      persistence_writer: persistence_writer,
      shared_doc: shared_doc
    } = setup_data

    # Monitor all processes
    doc_supervisor_ref = Process.monitor(doc_supervisor)
    persistence_writer_ref = Process.monitor(persistence_writer)
    shared_doc_ref = Process.monitor(shared_doc)

    {doc_supervisor_ref, persistence_writer_ref, shared_doc_ref}
  end

  # Helper to assert all processes terminated
  defp assert_all_processes_terminated(
         {doc_supervisor, persistence_writer, shared_doc},
         {doc_supervisor_ref, persistence_writer_ref, shared_doc_ref},
         expected_reasons \\ {:normal, :normal, :normal}
       ) do
    {doc_reason, pw_reason, sd_reason} = expected_reasons

    assert_receive {:DOWN, ^doc_supervisor_ref, :process, ^doc_supervisor,
                    ^doc_reason},
                   5000

    assert_receive {:DOWN, ^persistence_writer_ref, :process,
                    ^persistence_writer, ^pw_reason},
                   5000

    assert_receive {:DOWN, ^shared_doc_ref, :process, ^shared_doc, ^sd_reason},
                   5000

    refute Process.alive?(doc_supervisor)
    refute Process.alive?(persistence_writer)
    refute Process.alive?(shared_doc)
  end

  # Helper for crash testing pattern
  defp test_child_crash(
         setup_data,
         crashed_child,
         crash_reason,
         expected_outcomes
       ) do
    {_crashed_process, other_child_reason, supervisor_reason} = expected_outcomes

    # Monitor the processes that should terminate
    doc_supervisor_ref = Process.monitor(setup_data.doc_supervisor)

    other_child =
      if crashed_child == :persistence_writer,
        do: setup_data.shared_doc,
        else: setup_data.persistence_writer

    other_child_ref = Process.monitor(other_child)

    # Crash the specified child
    crashed_pid =
      if crashed_child == :persistence_writer,
        do: setup_data.persistence_writer,
        else: setup_data.shared_doc

    GenServer.stop(crashed_pid, crash_reason)

    # Verify expected termination cascade
    assert_receive {:DOWN, ^doc_supervisor_ref, :process, _, ^supervisor_reason},
                   5000

    assert_receive {:DOWN, ^other_child_ref, :process, _, ^other_child_reason},
                   5000

    # Verify all processes are down
    refute Process.alive?(setup_data.doc_supervisor)
    refute Process.alive?(setup_data.persistence_writer)
    refute Process.alive?(setup_data.shared_doc)

    verify_cleanup(setup_data.document_name, setup_data.workflow_id)
  end

  # Helper function to verify successful DocumentSupervisor initialization
  defp verify_initialization(%{
         workflow_id: workflow_id,
         document_name: document_name,
         doc_supervisor: doc_supervisor,
         persistence_writer: persistence_writer,
         shared_doc: shared_doc
       }) do
    # Verify DocumentSupervisor is registered correctly
    registered_supervisor = Registry.whereis({:doc_supervisor, document_name})
    assert registered_supervisor == doc_supervisor

    # Verify SharedDoc is in process group (now keyed by document_name, not workflow_id)
    members = :pg.get_members(:workflow_collaboration, document_name)
    assert shared_doc in members

    # Verify both processes are monitored by checking state
    state = :sys.get_state(doc_supervisor)
    assert is_reference(state.persistence_writer_ref)
    assert is_reference(state.shared_doc_ref)
    assert state.persistence_writer_pid == persistence_writer
    assert state.shared_doc_pid == shared_doc
    assert state.workflow.id == workflow_id

    # Verify all processes are grouped correctly in Registry
    group = Registry.get_group(document_name)
    assert Map.has_key?(group, :persistence_writer)
    assert Map.has_key?(group, :shared_doc)
    assert Map.has_key?(group, :doc_supervisor)

    # Count all registered processes for this workflow
    assert Registry.count(document_name) == 3
  end

  # Helper function to test DocumentSupervisor startup failure
  defp assert_startup_fails(start_args, expected_error_pattern \\ nil) do
    Process.flag(:trap_exit, true)

    {pid, ref} =
      spawn_monitor(fn ->
        case start_args do
          {args, opts} -> DocumentSupervisor.start_link(args, opts)
          args -> DocumentSupervisor.start_link(args)
        end
      end)

    if expected_error_pattern do
      assert_receive {:DOWN, ^ref, :process, ^pid, ^expected_error_pattern}, 1000
    else
      assert_receive {:DOWN, ^ref, :process, ^pid, _reason}, 1000
    end
  end

  describe "1. Initialization and Process Starting" do
    test "1.1 - Successful Initialization", context do
      setup_data = setup_document_supervisor(context)

      # Verify all initialization aspects are correct
      verify_initialization(setup_data)

      # Clean up
      GenServer.stop(setup_data.doc_supervisor, :normal)

      # Ensure all processes are stopped
      refute_eventually(Process.alive?(setup_data.doc_supervisor))
      refute_eventually(Process.alive?(setup_data.persistence_writer))
      refute_eventually(Process.alive?(setup_data.shared_doc))
    end

    test "1.2 - Missing Required Parameters" do
      # Test starting without workflow - should crash with KeyError
      assert_startup_fails([])

      # Test starting with empty args and empty GenServer options
      assert_startup_fails({[], []})

      # Test with nil workflow - should fail when building document name
      assert_startup_fails(workflow: nil)
    end
  end

  describe "2. Process Monitoring and Failure Handling" do
    setup :setup_document_supervisor

    test "2.1 - PersistenceWriter Crashes", context do
      # Test crash propagation: crashed child -> other child -> supervisor all get same reason
      capture_log(fn ->
        test_child_crash(
          context,
          :persistence_writer,
          :abnormal_termination,
          {:abnormal_termination, :abnormal_termination, :abnormal_termination}
        )
      end)
    end

    test "2.2 - SharedDoc Crashes", context do
      # Test crash propagation: SharedDoc crashes -> PersistenceWriter stops normally -> supervisor gets crash reason
      capture_log(fn ->
        test_child_crash(
          context,
          :shared_doc,
          :abnormal_termination,
          {:abnormal_termination, :normal, :abnormal_termination}
        )
      end)
    end

    test "2.3 - Handling Normal Child Exit", context do
      # Test normal exit handling: child exits normally -> all processes exit normally
      test_child_crash(
        context,
        :shared_doc,
        :normal,
        {:normal, :normal, :normal}
      )
    end
  end

  describe "3. Termination and Cleanup" do
    setup :setup_document_supervisor

    test "3.1 - Normal Termination", context do
      monitor_refs = monitor_and_verify_termination(context)

      # Stop DocumentSupervisor normally
      GenServer.stop(context.doc_supervisor, :normal)

      # Verify all processes terminate with expected reasons
      processes =
        {context.doc_supervisor, context.persistence_writer, context.shared_doc}

      assert_all_processes_terminated(processes, monitor_refs)

      verify_cleanup(context.document_name, context.workflow_id)
    end

    test "3.2 - Termination with Already Dead Children", context do
      # Monitor processes before killing any
      {doc_supervisor_ref, _pw_ref, shared_doc_ref} =
        monitor_and_verify_termination(context)

      capture_log(fn ->
        # Kill one child - this causes DocumentSupervisor to terminate due to monitoring
        GenServer.stop(context.persistence_writer, :kill)

        # Verify supervisor and remaining child terminate with :kill reason
        doc_supervisor = context.doc_supervisor
        shared_doc = context.shared_doc

        assert_receive {:DOWN, ^doc_supervisor_ref, :process, ^doc_supervisor,
                        :kill},
                       5000

        assert_receive {:DOWN, ^shared_doc_ref, :process, ^shared_doc, :kill},
                       5000

        refute Process.alive?(context.doc_supervisor)
        refute Process.alive?(context.persistence_writer)
        refute Process.alive?(context.shared_doc)
      end)

      verify_cleanup(context.document_name, context.workflow_id)
    end

    test "3.3 - Termination Order Verification", context do
      # Monitor child processes with timestamps
      persistence_writer_ref = Process.monitor(context.persistence_writer)
      shared_doc_ref = Process.monitor(context.shared_doc)
      start_time = System.monotonic_time(:millisecond)

      GenServer.stop(context.doc_supervisor, :normal)

      # Collect termination timestamps
      shared_doc_time =
        receive do
          {:DOWN, ^shared_doc_ref, :process, _, _} ->
            System.monotonic_time(:millisecond) - start_time
        after
          6000 -> flunk("SharedDoc did not terminate within timeout")
        end

      persistence_writer_time =
        receive do
          {:DOWN, ^persistence_writer_ref, :process, _, _} ->
            System.monotonic_time(:millisecond) - start_time
        after
          1000 -> flunk("PersistenceWriter did not terminate within timeout")
        end

      # Verify termination order: SharedDoc should terminate before or with PersistenceWriter
      assert shared_doc_time <= persistence_writer_time,
             "Termination order incorrect. SharedDoc: #{shared_doc_time}ms, " <>
               "PersistenceWriter: #{persistence_writer_time}ms"

      refute Process.alive?(context.doc_supervisor)
      verify_cleanup(context.document_name, context.workflow_id)
    end
  end

  describe "4. Child Spec Configuration" do
    test "4.1 - Child Spec Generation", context do
      workflow = context.workflow
      document_name = context.document_name

      # Test with various options
      basic_opts = [workflow: workflow, document_name: document_name]
      spec1 = DocumentSupervisor.child_spec(basic_opts)

      assert %{
               start: {DocumentSupervisor, :start_link, [^basic_opts, []]},
               type: :worker,
               restart: :transient,
               shutdown: 5000,
               id: id
             } = spec1

      # Generated UUID
      assert is_binary(id)

      # Test with provided id
      custom_id = "custom_supervisor_id"

      opts_with_id = [
        workflow: workflow,
        document_name: document_name,
        id: custom_id
      ]

      spec2 = DocumentSupervisor.child_spec(opts_with_id)

      assert spec2.id == custom_id

      assert spec2.start ==
               {DocumentSupervisor, :start_link,
                [[workflow: workflow, document_name: document_name], []]}

      # Test with name option (should be separated into GenServer opts)
      name_opts = [
        workflow: workflow,
        document_name: document_name,
        name: {:via, Registry, "test_name"}
      ]

      spec3 = DocumentSupervisor.child_spec(name_opts)

      assert spec3.start ==
               {DocumentSupervisor, :start_link,
                [
                  [workflow: workflow, document_name: document_name],
                  [name: {:via, Registry, "test_name"}]
                ]}

      # Test id generation - each call should produce unique id
      spec4 =
        DocumentSupervisor.child_spec(
          workflow: workflow,
          document_name: document_name
        )

      spec5 =
        DocumentSupervisor.child_spec(
          workflow: workflow,
          document_name: document_name
        )

      assert spec4.id != spec5.id
    end

    test "4.2 - Restart Strategy", context do
      setup_data = setup_test_supervisor(context)

      # Start the DocumentSupervisor as a child
      {:ok, doc_supervisor} =
        DynamicSupervisor.start_child(
          setup_data.test_supervisor,
          setup_data.child_spec
        )

      # Verify it's alive and registered
      assert Process.alive?(doc_supervisor)

      assert Registry.whereis({:doc_supervisor, context.document_name}) ==
               doc_supervisor

      # Test transient behavior - normal exit should NOT restart
      doc_supervisor_ref = Process.monitor(doc_supervisor)
      GenServer.stop(doc_supervisor, :normal)

      # Wait for normal termination
      assert_receive {:DOWN, ^doc_supervisor_ref, :process, ^doc_supervisor,
                      :normal},
                     5000

      # Verify no restart occurred for normal termination
      # Wait a reasonable time to ensure supervisor doesn't restart
      refute_eventually(
        Registry.whereis({:doc_supervisor, context.document_name}) != nil,
        1000
      )

      # Test abnormal crash - should restart with transient strategy
      # Start another child with same spec
      {:ok, doc_supervisor2} =
        DynamicSupervisor.start_child(
          setup_data.test_supervisor,
          setup_data.child_spec
        )

      doc_supervisor2_ref = Process.monitor(doc_supervisor2)

      # Monitor the supervisor itself to detect restart events
      test_supervisor_ref = Process.monitor(setup_data.test_supervisor)

      capture_log(fn ->
        # Kill the process abnormally
        Process.exit(doc_supervisor2, :kill)

        assert_receive {:DOWN, ^doc_supervisor2_ref, :process, ^doc_supervisor2,
                        :killed},
                       5000

        # Wait for the supervisor to restart the child
        assert_eventually(
          Registry.whereis({:doc_supervisor, context.document_name}) != nil,
          2000
        )

        # Verify the restarted process is different
        restarted_supervisor =
          Registry.whereis({:doc_supervisor, context.document_name})

        assert restarted_supervisor != doc_supervisor2
        assert Process.alive?(restarted_supervisor)
      end)

      # Verify the test supervisor itself is still alive (didn't crash due to child failure)
      assert Process.alive?(setup_data.test_supervisor)
      Process.demonitor(test_supervisor_ref, [:flush])

      # Clean up test supervisor
      DynamicSupervisor.stop(setup_data.test_supervisor)
    end
  end

  describe "5. Registry Integration" do
    setup :setup_document_supervisor

    test "5.1 - Registry Registration", %{
      workflow_id: workflow_id,
      document_name: document_name,
      doc_supervisor: doc_supervisor,
      persistence_writer: persistence_writer,
      shared_doc: shared_doc
    } do
      # Test all processes are registered correctly using pattern matching
      assert %{
               doc_supervisor: ^doc_supervisor,
               persistence_writer: ^persistence_writer,
               shared_doc: ^shared_doc
             } = Registry.get_group(document_name)

      # Test count function
      assert Registry.count(document_name) == 3

      # Clean up
      GenServer.stop(doc_supervisor, :normal)
      verify_cleanup(document_name, workflow_id)
    end

    test "5.2 - Process Group Registration", %{
      workflow_id: workflow_id,
      document_name: document_name,
      doc_supervisor: doc_supervisor,
      shared_doc: shared_doc
    } do
      # Test SharedDoc is the only member in workflow_collaboration process group
      assert [^shared_doc] =
               :pg.get_members(:workflow_collaboration, document_name)

      assert [^shared_doc] =
               :pg.get_local_members(:workflow_collaboration, document_name)

      # Clean up and verify process group is cleaned up
      GenServer.stop(doc_supervisor, :normal)
      verify_cleanup(document_name, workflow_id)
    end
  end

  describe "6. Edge Cases and Error Scenarios" do
    setup :setup_document_supervisor

    test "6.1 - Rapid Child Restarts", %{
      workflow_id: workflow_id,
      document_name: document_name,
      doc_supervisor: doc_supervisor
    } do
      # Monitor the DocumentSupervisor for termination
      doc_supervisor_ref = Process.monitor(doc_supervisor)

      capture_log(fn ->
        # Rapidly kill the same child multiple times to simulate rapid failures
        # DocumentSupervisor should handle this gracefully and terminate cleanly
        persistence_writer =
          Registry.whereis({:persistence_writer, document_name})

        shared_doc = Registry.whereis({:shared_doc, document_name})

        # Kill persistence_writer first
        GenServer.stop(persistence_writer, :kill)

        # The DocumentSupervisor should terminate due to monitoring
        assert_receive {:DOWN, ^doc_supervisor_ref, :process, ^doc_supervisor,
                        :kill},
                       5000

        # Verify all processes are properly cleaned up
        refute Process.alive?(doc_supervisor)
        refute Process.alive?(persistence_writer)
        refute Process.alive?(shared_doc)
      end)

      verify_cleanup(document_name, workflow_id)
    end

    test "6.2 - Concurrent Stop Requests", %{
      workflow_id: workflow_id,
      document_name: document_name,
      doc_supervisor: doc_supervisor
    } do
      # Monitor the DocumentSupervisor
      doc_supervisor_ref = Process.monitor(doc_supervisor)

      # Capture expected error logs from concurrent stop attempts
      log_output =
        capture_log(fn ->
          # Send multiple concurrent stop requests - catch exits to handle race conditions
          tasks =
            for i <- 1..5 do
              Task.async(fn ->
                try do
                  # Each task tries to stop with a different reason
                  reason = :"stop_reason_#{i}"
                  GenServer.stop(doc_supervisor, reason, 1000)
                catch
                  :exit, _ -> :already_stopped
                end
              end)
            end

          # Wait for the first stop to complete - only one should succeed
          assert_receive {:DOWN, ^doc_supervisor_ref, :process, ^doc_supervisor,
                          reason},
                         5000

          # Verify the reason is one of our stop reasons
          assert reason in [
                   :stop_reason_1,
                   :stop_reason_2,
                   :stop_reason_3,
                   :stop_reason_4,
                   :stop_reason_5
                 ]

          # Wait for all tasks to complete (most will get :already_stopped)
          results = Task.await_many(tasks, 2000)

          # At least one task should succeed with :ok, others should return :already_stopped
          successes = Enum.count(results, &(&1 == :ok))
          already_stopped = Enum.count(results, &(&1 == :already_stopped))
          assert successes >= 1
          assert already_stopped >= 0

          # Verify cleanup happened only once - no orphaned processes
          refute Process.alive?(doc_supervisor)
          verify_cleanup(document_name, workflow_id)
        end)

      # Verify we captured the expected concurrent termination error
      assert log_output =~ ~r/terminating.*\*\* \(stop\) :stop_reason_\d/s
    end

    test "6.3 - Process Already Stopping", %{
      workflow_id: workflow_id,
      document_name: document_name,
      doc_supervisor: doc_supervisor,
      shared_doc: shared_doc
    } do
      # Monitor the DocumentSupervisor
      doc_supervisor_ref = Process.monitor(doc_supervisor)

      capture_log(fn ->
        # Start shutdown process by stopping DocumentSupervisor
        Task.async(fn ->
          GenServer.stop(doc_supervisor, :shutdown, :infinity)
        end)

        # Give it a moment to start the termination process
        Process.sleep(50)

        # While DocumentSupervisor is stopping, try to kill one of its children
        # This simulates a child dying during the supervisor's termination sequence
        try do
          GenServer.stop(shared_doc, :kill)
        catch
          :exit, _ -> :already_stopping
        end

        # DocumentSupervisor should handle this gracefully and continue shutdown
        assert_receive {:DOWN, ^doc_supervisor_ref, :process, ^doc_supervisor,
                        :shutdown},
                       5000
      end)

      verify_cleanup(document_name, workflow_id)
    end
  end

  describe "7. Integration Points" do
    test "7.1 - With Lightning.Collaborate", %{workflow: workflow} do
      workflow_id = workflow.id
      document_name = "workflow:#{workflow_id}"
      user = insert(:user)

      # Test that Lightning.Collaborate.start/1 creates DocumentSupervisor through session
      {:ok, session} =
        Lightning.Collaborate.start(workflow: workflow, user: user)

      # Verify DocumentSupervisor is created and registered
      doc_supervisor = Registry.whereis({:doc_supervisor, document_name})
      assert doc_supervisor != nil

      # Verify all expected processes are registered
      assert %{
               doc_supervisor: ^doc_supervisor,
               persistence_writer: _persistence_writer,
               shared_doc: shared_doc
             } = Registry.get_group(document_name)

      # Verify SharedDoc is in process group
      assert [^shared_doc] =
               :pg.get_members(:workflow_collaboration, document_name)

      # Clean up session which should clean up DocumentSupervisor
      # Capture potential race condition logs during process shutdown
      capture_log(fn ->
        GenServer.stop(session, :normal)
        verify_cleanup(document_name, workflow_id)
      end)
    end

    setup :setup_document_supervisor

    test "7.2 - With Session Processes", %{
      workflow_id: _workflow_id,
      document_name: document_name,
      shared_doc: shared_doc
    } do
      # Both discovery methods should find the same process
      found_via_registry = Registry.whereis({:shared_doc, document_name})
      [found_via_pg] = :pg.get_members(:workflow_collaboration, document_name)

      assert found_via_registry == shared_doc
      assert found_via_pg == shared_doc
      assert found_via_registry == found_via_pg
    end

    test "7.3 - Persistence Flow", %{
      workflow_id: workflow_id,
      document_name: document_name,
      shared_doc: shared_doc,
      persistence_writer: persistence_writer
    } do
      # Test that stopping SharedDoc triggers flush_and_stop on PersistenceWriter
      shared_doc_ref = Process.monitor(shared_doc)
      persistence_writer_ref = Process.monitor(persistence_writer)

      # Stop SharedDoc which should trigger persistence flush
      GenServer.stop(shared_doc, :normal)

      # Both should terminate - SharedDoc first, then PersistenceWriter
      assert_receive {:DOWN, ^shared_doc_ref, :process, ^shared_doc, :normal},
                     5000

      assert_receive {:DOWN, ^persistence_writer_ref, :process,
                      ^persistence_writer, :normal},
                     5000

      # Cleanup is handled by DocumentSupervisor monitoring
      verify_cleanup(document_name, workflow_id)
    end
  end

  describe "8. Resource Management" do
    test "8.1 - Memory Leaks", %{workflow: workflow} do
      workflow_id = workflow.id
      document_name = "workflow:#{workflow_id}"

      # Test multiple start/stop cycles to detect resource leaks
      for _i <- 1..3 do
        # Start DocumentSupervisor
        {:ok, doc_supervisor} =
          DocumentSupervisor.start_link(
            [workflow: workflow, document_name: document_name],
            name: Registry.via({:doc_supervisor, document_name})
          )

        # Verify all processes are created and registered
        assert %{
                 doc_supervisor: ^doc_supervisor,
                 persistence_writer: _persistence_writer,
                 shared_doc: shared_doc
               } = Registry.get_group(document_name)

        # Verify process group membership
        assert [^shared_doc] =
                 :pg.get_members(:workflow_collaboration, document_name)

        # Stop DocumentSupervisor normally
        GenServer.stop(doc_supervisor, :normal)

        # Verify complete cleanup after each cycle
        verify_cleanup(document_name, workflow_id)
      end
    end

    test "8.2 - Timeout Handling", %{workflow: workflow} do
      workflow_id = workflow.id
      document_name = "workflow:#{workflow_id}"

      # Start DocumentSupervisor
      {:ok, doc_supervisor} =
        DocumentSupervisor.start_link(
          [workflow: workflow, document_name: document_name],
          name: Registry.via({:doc_supervisor, document_name})
        )

      shared_doc = Registry.whereis({:shared_doc, document_name})

      # Make SharedDoc unresponsive by suspending it
      :sys.suspend(shared_doc)

      # Monitor DocumentSupervisor termination
      doc_supervisor_ref = Process.monitor(doc_supervisor)

      # Start termination - DocumentSupervisor should handle unresponsive child
      Task.async(fn -> GenServer.stop(doc_supervisor, :shutdown, 10_000) end)

      # DocumentSupervisor should terminate despite unresponsive child
      assert_receive {:DOWN, ^doc_supervisor_ref, :process, ^doc_supervisor,
                      :shutdown},
                     15_000

      verify_cleanup(document_name, workflow_id)
    end
  end
end
