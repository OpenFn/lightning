defmodule Lightning.WorkOrderTest do
  use Lightning.DataCase, async: true

  import Lightning.Factories

  alias Lightning.WorkOrder

  describe "changeset/2" do
    test "must have a workflow" do
      errors = WorkOrder.changeset(%WorkOrder{}, %{}) |> errors_on()

      assert errors[:workflow_id] == ["can't be blank"]
      assert errors[:last_activity] == ["can't be blank"]
    end
  end

  describe "snapshotting" do
    test "must belong to a snapshot" do
      workflow = insert(:workflow)

      change(%WorkOrder{}, workflow_id: workflow.id)
      |> WorkOrder.validate()
      |> Repo.insert!()
    end

    test "ensures trigger is from the snapshot" do
      workflow = insert(:simple_workflow)

      {:ok, snapshot} = Lightning.Workflows.Snapshot.create(workflow)

      [trigger] = workflow.triggers

      work_order =
        change(%WorkOrder{},
          workflow_id: workflow.id,
          trigger_id: trigger.id,
          snapshot_id: snapshot.id
        )
        |> WorkOrder.validate()
        |> Repo.insert!()

      assert work_order.snapshot_id == snapshot.id

      # By deleting the trigger, we should still have the id on the work order
      Repo.delete!(trigger)
      work_order = Repo.reload(work_order)

      assert work_order |> Map.get(:trigger_id) == trigger.id,
             "work_order should still be assigned to the trigger"
    end
  end

  describe "outcome/1" do
    test "buckets every state in states()" do
      for state <- WorkOrder.states() do
        assert WorkOrder.outcome(state) in [
                 :success,
                 :cancelled,
                 :pending,
                 :failed
               ]
      end
    end

    test "success and cancelled are their own outcome, not failed" do
      assert WorkOrder.outcome(:success) == :success
      assert WorkOrder.outcome(:cancelled) == :cancelled
    end

    test "active states are pending" do
      for state <- WorkOrder.active_states() do
        assert WorkOrder.outcome(state) == :pending
      end
    end
  end

  describe "failure_states/0" do
    test "is every final state except success and cancelled" do
      # If this fails because a state was added or removed, also update
      # assets/js/health/types.ts's FAILURE_STATES to match.
      assert WorkOrder.failure_states() == [
               :rejected,
               :failed,
               :crashed,
               :killed,
               :exception,
               :lost
             ]
    end
  end
end
