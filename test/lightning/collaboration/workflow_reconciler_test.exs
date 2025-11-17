defmodule Lightning.Collaboration.WorkflowReconcilerTest do
  # Tests must be async: false because we put a SharedDoc in a dynamic supervisor
  # that isn't owned by the test process. So we need our Ecto sandbox to be
  # in shared mode.
  use Lightning.DataCase, async: false

  import Lightning.Factories
  import Lightning.CollaborationHelpers

  alias Lightning.Collaborate
  alias Lightning.Collaboration.{Session, WorkflowReconciler}
  alias Lightning.Workflows

  # we assume that the WorkflowCollaboration supervisor is up
  # that starts :pg with the :workflow_collaboration scope
  # and a dynamic supervisor called Lightning.WorkflowCollaboration

  setup do
    # Set global mode for the mock to allow cross-process calls
    Mox.set_mox_global(LightningMock)
    # Stub the broadcast calls that WorkflowReconciler makes
    Mox.stub(LightningMock, :broadcast, fn _topic, _message -> :ok end)

    user = insert(:user)
    {:ok, user: user}
  end

  describe "reconcile_workflow_changes/2" do
    setup do
      workflow = insert(:complex_workflow)

      on_exit(fn ->
        ensure_doc_supervisor_stopped(workflow.id)
      end)

      %{workflow: workflow}
    end

    test "job insert operations are applied to YDoc", %{
      user: user,
      workflow: workflow
    } do
      # Start a session to create the SharedDoc
      {:ok, session_pid} =
        Collaborate.start(workflow: workflow, user: user)

      # Create a new job changeset
      new_job =
        build(:job,
          workflow: workflow,
          name: "New Test Job",
          body: "console.log('new job');",
          adaptor: "@openfn/language-http@latest"
        )

      # Create changeset for inserting the job
      workflow_changeset =
        workflow
        |> Workflows.change_workflow()
        |> Ecto.Changeset.put_assoc(:jobs, workflow.jobs ++ [new_job])
        |> Map.put(:action, :update)

      # Add the job changeset with insert action
      job_changeset = Ecto.Changeset.change(new_job) |> Map.put(:action, :insert)

      workflow_changeset = %{
        workflow_changeset
        | changes: Map.put(workflow_changeset.changes, :jobs, [job_changeset])
      }

      shared_doc = Session.get_doc(session_pid)
      Yex.Doc.monitor_update(shared_doc)

      # Reconcile the changes
      WorkflowReconciler.reconcile_workflow_changes(workflow_changeset, workflow)

      assert_one_update(shared_doc)

      jobs_array = Yex.Doc.get_array(shared_doc, "jobs")

      # Should have original 7 jobs + 1 new job
      assert Yex.Array.length(jobs_array) == 8

      # Find the new job in the YDoc
      new_job_data = find_in_ydoc_array(jobs_array, new_job.id)

      assert %{
               "name" => "New Test Job",
               "body" => "console.log('new job');",
               "adaptor" => "@openfn/language-http@latest"
             } = new_job_data

      Session.stop(session_pid)
      ensure_doc_supervisor_stopped(workflow.id)
    end

    test "job update operations are applied to YDoc", %{
      user: user,
      workflow: workflow
    } do
      # Start a session to create the SharedDoc
      {:ok, session_pid} =
        Collaborate.start(workflow: workflow, user: user)

      # Get the SharedDoc and verify initial state
      shared_doc = Session.get_doc(session_pid)
      Yex.Doc.monitor_update(shared_doc)

      jobs_array = Yex.Doc.get_array(shared_doc, "jobs")

      # Get the first job ID from the YDoc to ensure we update an existing job
      first_job_in_ydoc = Yex.Array.fetch!(jobs_array, 0)
      job_id_to_update = Yex.Map.fetch!(first_job_in_ydoc, "id")

      # Find the corresponding job in the workflow
      job_to_update = Enum.find(workflow.jobs, &(&1.id == job_id_to_update))

      assert job_to_update != nil,
             "Job with ID #{job_id_to_update} not found in workflow"

      # Create changeset for updating the job
      workflow_changeset =
        workflow
        |> Workflows.change_workflow()
        |> Map.put(:action, :update)

      # Create job changeset with update action and changes
      job_changeset =
        Ecto.Changeset.change(job_to_update, %{
          name: "Updated Job Name",
          body: "console.log('updated');",
          adaptor: "@openfn/language-common@latest"
        })
        |> Map.put(:action, :update)

      workflow_changeset = %{
        workflow_changeset
        | changes: Map.put(workflow_changeset.changes, :jobs, [job_changeset])
      }

      # Reconcile the changes
      WorkflowReconciler.reconcile_workflow_changes(workflow_changeset, workflow)

      assert_one_update(shared_doc)

      # Verify the job was updated in the YDoc
      updated_jobs_array = Yex.Doc.get_array(shared_doc, "jobs")

      # Find the updated job in the YDoc
      updated_job_data =
        find_in_ydoc_array(updated_jobs_array, job_id_to_update)

      assert %{
               "name" => "Updated Job Name",
               "body" => "console.log('updated');",
               "adaptor" => "@openfn/language-common@latest"
             } =
               updated_job_data

      Session.stop(session_pid)
      ensure_doc_supervisor_stopped(workflow.id)
    end

    test "job delete operations are applied to YDoc", %{
      user: user,
      workflow: workflow
    } do
      # Start a session to create the SharedDoc
      {:ok, session_pid} =
        Collaborate.start(workflow: workflow, user: user)

      # Get the first job to delete
      job_to_delete = Enum.at(workflow.jobs, 0)
      remaining_jobs = Enum.reject(workflow.jobs, &(&1.id == job_to_delete.id))

      # Create changeset for deleting the job
      workflow_changeset =
        workflow
        |> Workflows.change_workflow()
        |> Ecto.Changeset.put_assoc(:jobs, remaining_jobs)
        |> Map.put(:action, :update)

      # Create job changeset with delete action
      job_changeset =
        Ecto.Changeset.change(job_to_delete) |> Map.put(:action, :delete)

      workflow_changeset = %{
        workflow_changeset
        | changes: Map.put(workflow_changeset.changes, :jobs, [job_changeset])
      }

      # Reconcile the changes
      WorkflowReconciler.reconcile_workflow_changes(workflow_changeset, workflow)

      # Verify the job was removed from the YDoc
      shared_doc = Session.get_doc(session_pid)
      jobs_array = Yex.Doc.get_array(shared_doc, "jobs")

      # Should have 6 jobs instead of 7
      assert Yex.Array.length(jobs_array) == 6

      # Verify the deleted job is no longer in the YDoc
      refute find_in_ydoc_array(jobs_array, job_to_delete.id)

      Session.stop(session_pid)
      ensure_doc_supervisor_stopped(workflow.id)
    end

    test "edge insert operations are applied to YDoc", %{
      user: user,
      workflow: workflow
    } do
      # Start a session to create the SharedDoc
      {:ok, session_pid} =
        Collaborate.start(workflow: workflow, user: user)

      # Create a new edge between existing jobs
      %{id: source_job_id} = source_job = Enum.at(workflow.jobs, 1)
      %{id: target_job_id} = target_job = Enum.at(workflow.jobs, 3)

      new_edge =
        build(:edge,
          workflow: workflow,
          source_job_id: source_job.id,
          target_job_id: target_job.id,
          condition_type: :on_job_success,
          enabled: true
        )

      # Create changeset for inserting the edge
      workflow_changeset =
        workflow
        |> Workflows.change_workflow()
        |> Ecto.Changeset.put_assoc(:edges, workflow.edges ++ [new_edge])
        |> Map.put(:action, :update)

      # Create edge changeset with insert action
      edge_changeset =
        Ecto.Changeset.change(new_edge) |> Map.put(:action, :insert)

      workflow_changeset = %{
        workflow_changeset
        | changes: Map.put(workflow_changeset.changes, :edges, [edge_changeset])
      }

      # Reconcile the changes
      WorkflowReconciler.reconcile_workflow_changes(workflow_changeset, workflow)

      # Verify the edge was added to the YDoc
      shared_doc = Session.get_doc(session_pid)
      edges_array = Yex.Doc.get_array(shared_doc, "edges")

      # Should have original 7 edges + 1 new edge
      assert Yex.Array.length(edges_array) == 8

      # Find the new edge in the YDoc
      new_edge_data = find_in_ydoc_array(edges_array, new_edge.id)

      assert %{
               "source_job_id" => ^source_job_id,
               "target_job_id" => ^target_job_id,
               "condition_type" => "on_job_success",
               "enabled" => true
             } = new_edge_data
    end

    test "edge update operations are applied to YDoc", %{
      user: user,
      workflow: workflow
    } do
      # Start a session to create the SharedDoc
      {:ok, session_pid} =
        Collaborate.start(workflow: workflow, user: user)

      # Get the first edge to update
      edge_to_update = Enum.at(workflow.edges, 0)

      # Create changeset for updating the edge
      workflow_changeset =
        workflow
        |> Workflows.change_workflow()
        |> Map.put(:action, :update)

      # Create edge changeset with update action
      edge_changeset =
        Ecto.Changeset.change(edge_to_update, %{
          condition_type: :on_job_failure,
          enabled: false
        })
        |> Map.put(:action, :update)

      workflow_changeset = %{
        workflow_changeset
        | changes: Map.put(workflow_changeset.changes, :edges, [edge_changeset])
      }

      # Reconcile the changes
      WorkflowReconciler.reconcile_workflow_changes(workflow_changeset, workflow)

      # Verify the edge was updated in the YDoc
      shared_doc = Session.get_doc(session_pid)
      edges_array = Yex.Doc.get_array(shared_doc, "edges")

      # Find the updated edge in the YDoc
      assert %{"condition_type" => "on_job_failure", "enabled" => false} =
               find_in_ydoc_array(edges_array, edge_to_update.id)
    end

    test "edge delete operations are applied to YDoc", %{
      user: user,
      workflow: workflow
    } do
      # Start a session to create the SharedDoc
      {:ok, session_pid} =
        Collaborate.start(workflow: workflow, user: user)

      # Get the first edge to delete
      edge_to_delete = Enum.at(workflow.edges, 0)

      remaining_edges =
        Enum.reject(workflow.edges, &(&1.id == edge_to_delete.id))

      # Create changeset for deleting the edge
      workflow_changeset =
        workflow
        |> Workflows.change_workflow()
        |> Ecto.Changeset.put_assoc(:edges, remaining_edges)
        |> Map.put(:action, :update)

      # Create edge changeset with delete action
      edge_changeset =
        Ecto.Changeset.change(edge_to_delete) |> Map.put(:action, :delete)

      workflow_changeset = %{
        workflow_changeset
        | changes: Map.put(workflow_changeset.changes, :edges, [edge_changeset])
      }

      # Reconcile the changes
      WorkflowReconciler.reconcile_workflow_changes(workflow_changeset, workflow)

      # Verify the edge was removed from the YDoc
      shared_doc = Session.get_doc(session_pid)
      edges_array = Yex.Doc.get_array(shared_doc, "edges")

      # Should have 6 edges instead of 7
      assert Yex.Array.length(edges_array) == 6

      # Verify the deleted edge is no longer in the YDoc
      deleted_edge_data = find_in_ydoc_array(edges_array, edge_to_delete.id)
      assert deleted_edge_data == nil
    end

    test "trigger update operations are applied to YDoc", %{
      user: user,
      workflow: workflow
    } do
      # Start a session to create the SharedDoc
      {:ok, session_pid} =
        Collaborate.start(workflow: workflow, user: user)

      # Get the first trigger to update
      trigger_to_update = Enum.at(workflow.triggers, 0)

      # Create changeset for updating the trigger
      workflow_changeset =
        workflow
        |> Workflows.change_workflow()
        |> Map.put(:action, :update)

      # Create trigger changeset with update action
      trigger_changeset =
        Ecto.Changeset.change(trigger_to_update, %{
          enabled: false,
          cron_expression: "0 0 * * *"
        })
        |> Map.put(:action, :update)

      workflow_changeset = %{
        workflow_changeset
        | changes:
            Map.put(workflow_changeset.changes, :triggers, [trigger_changeset])
      }

      # Reconcile the changes
      WorkflowReconciler.reconcile_workflow_changes(workflow_changeset, workflow)

      # Verify the trigger was updated in the YDoc
      shared_doc = Session.get_doc(session_pid)
      triggers_array = Yex.Doc.get_array(shared_doc, "triggers")

      # Find the updated trigger in the YDoc
      updated_trigger_data =
        find_in_ydoc_array(triggers_array, trigger_to_update.id)

      assert updated_trigger_data != nil

      assert %{"enabled" => false, "cron_expression" => "0 0 * * *"} =
               updated_trigger_data
    end

    test "trigger delete operations are applied to YDoc", %{
      user: user,
      workflow: workflow
    } do
      # Start a session to create the SharedDoc
      {:ok, session_pid} =
        Collaborate.start(workflow: workflow, user: user)

      # Get the trigger to delete
      trigger_to_delete = Enum.at(workflow.triggers, 0)

      # Create changeset for deleting the trigger
      workflow_changeset =
        workflow
        |> Workflows.change_workflow()
        |> Ecto.Changeset.put_assoc(:triggers, [])
        |> Map.put(:action, :update)

      # Create trigger changeset with delete action
      trigger_changeset =
        Ecto.Changeset.change(trigger_to_delete) |> Map.put(:action, :delete)

      workflow_changeset = %{
        workflow_changeset
        | changes:
            Map.put(workflow_changeset.changes, :triggers, [trigger_changeset])
      }

      # Reconcile the changes
      WorkflowReconciler.reconcile_workflow_changes(workflow_changeset, workflow)

      # Verify the trigger was removed from the YDoc
      shared_doc = Session.get_doc(session_pid)
      triggers_array = Yex.Doc.get_array(shared_doc, "triggers")

      # Should have 0 triggers instead of 1
      assert Yex.Array.length(triggers_array) == 0
    end

    test "workflow-level updates are applied to YDoc", %{
      user: user,
      workflow: workflow
    } do
      # Start a session to create the SharedDoc
      {:ok, session_pid} =
        Collaborate.start(workflow: workflow, user: user)

      # Create changeset for updating workflow properties
      workflow_changeset =
        workflow
        |> Workflows.change_workflow(%{
          name: "Updated Workflow Name",
          concurrency: 5
        })
        |> Map.put(:action, :update)

      # Reconcile the changes
      WorkflowReconciler.reconcile_workflow_changes(workflow_changeset, workflow)

      # Verify the workflow was updated in the YDoc
      shared_doc = Session.get_doc(session_pid)
      workflow_map = Yex.Doc.get_map(shared_doc, "workflow")

      assert Yex.Map.fetch!(workflow_map, "name") == "Updated Workflow Name"
      assert Yex.Map.fetch!(workflow_map, "concurrency") == 5
    end

    test "lock_version updates are applied to YDoc", %{
      user: user,
      workflow: workflow
    } do
      # Start a session to create the SharedDoc
      {:ok, session_pid} =
        Collaborate.start(workflow: workflow, user: user)

      # Get initial lock_version from YDoc
      shared_doc = Session.get_doc(session_pid)
      workflow_map = Yex.Doc.get_map(shared_doc, "workflow")
      initial_lock_version = Yex.Map.fetch!(workflow_map, "lock_version")

      # Simulate a save operation that increments lock_version
      new_lock_version = initial_lock_version + 1

      # Create changeset with updated lock_version
      # Note: lock_version is managed by optimistic_lock() so we manually
      # add it to changes to simulate what happens after a real save
      workflow_changeset =
        workflow
        |> Workflows.change_workflow(%{})
        |> Ecto.Changeset.put_change(:lock_version, new_lock_version)
        |> Map.put(:action, :update)

      Yex.Doc.monitor_update(shared_doc)

      # Reconcile the changes
      WorkflowReconciler.reconcile_workflow_changes(workflow_changeset, workflow)

      # Verify exactly one update was sent
      assert_one_update(shared_doc)

      # Verify the lock_version was updated in the YDoc
      updated_workflow_map = Yex.Doc.get_map(shared_doc, "workflow")

      assert Yex.Map.fetch!(updated_workflow_map, "lock_version") ==
               new_lock_version

      Session.stop(session_pid)
      ensure_doc_supervisor_stopped(workflow.id)
    end

    test "positions updates are applied to YDoc", %{
      user: user,
      workflow: workflow
    } do
      # Start a session to create the SharedDoc
      {:ok, session_pid} =
        Collaborate.start(workflow: workflow, user: user)

      # Get some job IDs to create positions for
      job1_id = Enum.at(workflow.jobs, 0).id
      job2_id = Enum.at(workflow.jobs, 1).id
      job3_id = Enum.at(workflow.jobs, 2).id

      # Create positions map
      new_positions = %{
        job1_id => %{"x" => 100, "y" => 200},
        job2_id => %{"x" => 300, "y" => 400},
        job3_id => %{"x" => 500, "y" => 600}
      }

      # Create changeset for updating positions
      workflow_changeset =
        workflow
        |> Workflows.change_workflow(%{positions: new_positions})
        |> Map.put(:action, :update)

      shared_doc = Session.get_doc(session_pid)
      Yex.Doc.monitor_update(shared_doc)

      # Reconcile the changes
      WorkflowReconciler.reconcile_workflow_changes(workflow_changeset, workflow)

      assert_one_update(shared_doc)

      # Verify the positions were updated in the YDoc
      positions_map = Yex.Doc.get_map(shared_doc, "positions")

      assert Yex.Map.fetch!(positions_map, job1_id) == %{"x" => 100, "y" => 200}
      assert Yex.Map.fetch!(positions_map, job2_id) == %{"x" => 300, "y" => 400}
      assert Yex.Map.fetch!(positions_map, job3_id) == %{"x" => 500, "y" => 600}
    end

    test "multiple simultaneous changes are applied correctly", %{
      user: user,
      workflow: workflow
    } do
      # Start a session to create the SharedDoc
      {:ok, session_pid} =
        Collaborate.start(workflow: workflow, user: user)

      # Get existing entities to modify
      job_to_update = Enum.at(workflow.jobs, 0)
      edge_to_update = Enum.at(workflow.edges, 0)
      trigger_to_update = Enum.at(workflow.triggers, 0)

      # Create a new job to add
      new_job =
        build(:job,
          workflow: workflow,
          name: "Simultaneous Job",
          body: "console.log('simultaneous');"
        )

      # Create comprehensive changeset with multiple changes
      workflow_changeset =
        workflow
        |> Workflows.change_workflow(%{name: "Multi-Change Workflow"})
        |> Map.put(:action, :update)

      # Create individual changesets for each operation
      job_update_changeset =
        Ecto.Changeset.change(job_to_update, %{
          name: "Multi-Updated Job"
        })
        |> Map.put(:action, :update)

      job_insert_changeset =
        Ecto.Changeset.change(new_job) |> Map.put(:action, :insert)

      edge_update_changeset =
        Ecto.Changeset.change(edge_to_update, %{
          enabled: false
        })
        |> Map.put(:action, :update)

      trigger_update_changeset =
        Ecto.Changeset.change(trigger_to_update, %{
          enabled: false
        })
        |> Map.put(:action, :update)

      # Add all changes to the workflow changeset
      workflow_changeset = %{
        workflow_changeset
        | changes:
            Map.merge(workflow_changeset.changes, %{
              jobs: [job_update_changeset, job_insert_changeset],
              edges: [edge_update_changeset],
              triggers: [trigger_update_changeset]
            })
      }

      # Reconcile all changes at once
      WorkflowReconciler.reconcile_workflow_changes(workflow_changeset, workflow)

      # Verify all changes were applied
      shared_doc = Session.get_doc(session_pid)

      # Check workflow update
      workflow_map = Yex.Doc.get_map(shared_doc, "workflow")
      assert Yex.Map.fetch!(workflow_map, "name") == "Multi-Change Workflow"

      # Check job update and insert
      jobs_array = Yex.Doc.get_array(shared_doc, "jobs")
      # 7 original + 1 new
      assert Yex.Array.length(jobs_array) == 8

      assert %{"name" => "Multi-Updated Job"} =
               find_in_ydoc_array(jobs_array, job_to_update.id)

      assert %{"name" => "Simultaneous Job"} =
               find_in_ydoc_array(jobs_array, new_job.id)

      # Check edge update
      edges_array = Yex.Doc.get_array(shared_doc, "edges")

      assert %{"enabled" => false} =
               find_in_ydoc_array(edges_array, edge_to_update.id)

      # Check trigger update
      triggers_array = Yex.Doc.get_array(shared_doc, "triggers")

      assert %{"enabled" => false} =
               find_in_ydoc_array(triggers_array, trigger_to_update.id)
    end

    test "reconciliation with no active sessions does not crash", %{
      workflow: workflow
    } do
      # Don't start any session - no active SharedDoc

      # Create a changeset
      workflow_changeset =
        workflow
        |> Workflows.change_workflow(%{name: "No Sessions Workflow"})
        |> Map.put(:action, :update)

      # This should not crash
      assert :ok =
               WorkflowReconciler.reconcile_workflow_changes(
                 workflow_changeset,
                 workflow
               )
    end

    test "reconciliation handles large workflow modifications efficiently", %{
      user: user,
      workflow: workflow
    } do
      # Start a session to create the SharedDoc
      {:ok, session_pid} =
        Collaborate.start(workflow: workflow, user: user)

      # Create many new jobs at once (stress test)
      new_jobs =
        Enum.map(1..50, fn i ->
          build(:job,
            workflow: workflow,
            name: "Stress Job #{i}",
            body: "console.log('stress #{i}');"
          )
        end)

      # Create changeset with many inserts
      workflow_changeset =
        workflow
        |> Workflows.change_workflow()
        |> Map.put(:action, :update)

      job_changesets =
        Enum.map(new_jobs, fn job ->
          Ecto.Changeset.change(job) |> Map.put(:action, :insert)
        end)

      workflow_changeset = %{
        workflow_changeset
        | changes: Map.put(workflow_changeset.changes, :jobs, job_changesets)
      }

      # Measure performance
      start_time = System.monotonic_time(:millisecond)

      # Reconcile the changes
      WorkflowReconciler.reconcile_workflow_changes(workflow_changeset, workflow)

      end_time = System.monotonic_time(:millisecond)
      duration = end_time - start_time

      # Should complete within reasonable time (adjust threshold as needed)
      assert duration < 1000, "Reconciliation took too long: #{duration}ms"

      # Verify all jobs were added
      shared_doc = Session.get_doc(session_pid)
      jobs_array = Yex.Doc.get_array(shared_doc, "jobs")

      # Should have original 7 jobs + 50 new jobs
      assert Yex.Array.length(jobs_array) == 57
    end

    test "reconciliation handles concurrent sessions correctly", %{
      user: user,
      workflow: workflow
    } do
      # Start multiple sessions to create multiple references to SharedDoc
      {:ok, session1_pid} =
        Collaborate.start(workflow: workflow, user: user)

      {:ok, session2_pid} =
        Collaborate.start(workflow: workflow, user: user)

      {:ok, session3_pid} =
        Collaborate.start(workflow: workflow, user: user)

      # Verify all sessions share the same SharedDoc
      shared_doc1 = Session.get_doc(session1_pid)
      shared_doc2 = Session.get_doc(session2_pid)
      shared_doc3 = Session.get_doc(session3_pid)

      assert shared_doc1 == shared_doc2
      assert shared_doc2 == shared_doc3

      # Create a new job
      new_job =
        build(:job,
          workflow: workflow,
          name: "Concurrent Job",
          body: "console.log('concurrent');"
        )

      # Create changeset
      workflow_changeset =
        workflow
        |> Workflows.change_workflow()
        |> Map.put(:action, :update)

      job_changeset = Ecto.Changeset.change(new_job) |> Map.put(:action, :insert)

      workflow_changeset = %{
        workflow_changeset
        | changes: Map.put(workflow_changeset.changes, :jobs, [job_changeset])
      }

      # Reconcile the changes
      WorkflowReconciler.reconcile_workflow_changes(workflow_changeset, workflow)

      # All sessions should see the same updated data
      jobs_array1 = Yex.Doc.get_array(shared_doc1, "jobs")
      jobs_array2 = Yex.Doc.get_array(shared_doc2, "jobs")
      jobs_array3 = Yex.Doc.get_array(shared_doc3, "jobs")

      assert Yex.Array.length(jobs_array1) == 8
      assert Yex.Array.length(jobs_array2) == 8
      assert Yex.Array.length(jobs_array3) == 8

      # All should find the new job
      assert find_in_ydoc_array(jobs_array1, new_job.id)
      assert find_in_ydoc_array(jobs_array2, new_job.id)
      assert find_in_ydoc_array(jobs_array3, new_job.id)
    end
  end

  defp find_in_ydoc_array(array, id) do
    array
    |> Enum.reduce_while(nil, fn item, _ ->
      case item do
        %Yex.Map{} = map ->
          if Yex.Map.fetch!(map, "id") == id do
            Yex.Map.to_map(map)
          end

        e when is_map(e) ->
          if Map.get(e, "id") == id do
            e
          end
      end
      |> case do
        nil ->
          {:cont, nil}

        map ->
          {:halt, map}
      end
    end)
  end

  defp assert_one_update(shared_doc) do
    assert_receive {:update_v1, _, nil, ^shared_doc}

    refute_receive {:update_v1, _, nil, ^shared_doc},
                   nil,
                   "Got a second update to the SharedDoc"
  end
end
