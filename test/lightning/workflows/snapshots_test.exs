defmodule Lightning.Workflows.SnapshotsTest do
  use Lightning.DataCase, async: true

  alias Lightning.Workflows

  import Lightning.Factories

  test "from a workflow" do
    workflow = insert(:complex_workflow)

    Workflows.Snapshots.create(workflow)
    |> case do
      {:ok, snapshot} ->
        assert snapshot.name == workflow.name
        assert snapshot.jobs |> length() == 7
        assert snapshot.triggers |> length() == 1
        assert snapshot.edges |> length() == 7

      {:error, changeset} ->
        IO.inspect(changeset)
        flunk("expected snapshot to be created")
    end

    {:ok, workflow} =
      workflow
      |> Workflows.update_workflow(%{name: "new name", jobs: [params_for(:job)]})

    {:ok, snapshot} = Workflows.Snapshots.create(workflow)

    assert snapshot.name == workflow.name
    assert snapshot.jobs |> length() == 1
    assert snapshot.triggers |> length() == 1
    # TODO: edges should be cleaned up when jobs are removed, this requires
    # runs and steps to be disassociated from jobs
    assert snapshot.edges |> length() == 7

    snapshot = snapshot |> Lightning.Repo.reload!()

    [original_job] = workflow.jobs
    [snapshot_job] = snapshot.jobs

    assert snapshot_job.id == original_job.id
    assert snapshot_job.inserted_at == original_job.inserted_at
    assert snapshot_job.updated_at == original_job.updated_at

    [original_trigger] = workflow.triggers
    [snapshot_trigger] = snapshot.triggers

    assert snapshot_trigger.id == original_trigger.id
    assert snapshot_trigger.inserted_at == original_trigger.inserted_at
    assert snapshot_trigger.updated_at == original_trigger.updated_at
  end
end
