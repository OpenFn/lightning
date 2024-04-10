defmodule Lightning.Invocation.RunTest do
  use Lightning.DataCase, async: true

  alias Lightning.Run

  describe "changeset/2" do
    test "must have a work_order" do
      errors = Run.changeset(%Run{}, %{}) |> errors_on()

      assert errors[:work_order_id] == ["can't be blank"]
    end
  end

  describe "snapshotting" do
    test "must belong to a snapshot" do
      workflow = insert(:workflow)
      work_order = insert(:workorder, workflow: workflow)

      changeset = Run.changeset(%Run{}, %{work_order_id: work_order.id})

      refute changeset.valid?

      assert {:snapshot_id, ["can't be blank"]} in errors_on(changeset)
    end

    test "ensures starting_trigger is from the snapshot" do
      %{triggers: [trigger]} = workflow = insert(:simple_workflow)

      {:ok, snapshot} = Lightning.Workflows.Snapshot.create(workflow)

      work_order =
        insert(:workorder,
          workflow: workflow,
          snapshot: snapshot,
          dataclip: build(:dataclip)
        )

      run =
        Run.for(trigger, %{
          snapshot: snapshot,
          dataclip: work_order.dataclip
        })
        |> put_assoc(:work_order, work_order)
        |> Repo.insert!()

      assert run.snapshot_id == snapshot.id

      Repo.delete!(trigger)
      run = Repo.reload(run)

      assert run |> Map.get(:starting_trigger_id) == trigger.id,
             "run should still be assigned to the trigger"
    end

    test "ensures starting_job is from the snapshot" do
      %{jobs: [job]} = workflow = insert(:simple_workflow)

      {:ok, snapshot} = Lightning.Workflows.Snapshot.create(workflow)

      work_order =
        insert(:workorder,
          workflow: workflow,
          snapshot: snapshot,
          dataclip: build(:dataclip)
        )

      run =
        Run.for(job, %{
          created_by: insert(:user),
          snapshot: snapshot,
          dataclip: work_order.dataclip
        })
        |> put_assoc(:work_order, work_order)
        |> Repo.insert!()

      assert run.snapshot_id == snapshot.id

      Repo.delete!(job)
      run = Repo.reload(run)

      assert run |> Map.get(:starting_job_id) == job.id,
             "run should still be assigned to the job"
    end
  end
end
