defmodule Lightning.Workflows.SnapshotsTest do
  use Lightning.DataCase, async: true

  alias Lightning.Workflows

  import Lightning.Factories

  test "from a workflow" do
    workflow = insert(:complex_workflow)

    Workflows.Snapshot.create(workflow)
    |> case do
      {:ok, snapshot} ->
        assert snapshot.name == workflow.name
        assert snapshot.jobs |> length() == 7

        for original_job <- workflow.jobs do
          assert snapshot_job =
                   snapshot.jobs |> Enum.find(&(&1.id == original_job.id)),
                 "job not found in snapshot: #{inspect(original_job)}"

          assert_job_equal(snapshot_job, original_job)
        end

        assert snapshot.triggers |> length() == 1
        assert snapshot.edges |> length() == workflow.edges |> length()

        for original_edge <- workflow.edges do
          assert snapshot_edge =
                   snapshot.edges |> Enum.find(&(&1.id == original_edge.id)),
                 "edge not found in snapshot: #{inspect(original_edge)}"

          assert_edge_equal(snapshot_edge, original_edge)
        end

      {:error, changeset} ->
        IO.inspect(changeset)
        flunk("expected snapshot to be created")
    end

    {:ok, workflow} =
      workflow
      |> Workflows.change_workflow(%{name: "new name", jobs: [params_for(:job)]})
      |> Workflows.save_workflow()

    {:error, changeset} = Workflows.Snapshot.create(workflow)

    assert {
             :lock_version,
             {"exists for this workflow",
              [
                constraint: :unique,
                constraint_name:
                  "workflow_snapshots_workflow_id_lock_version_index"
              ]}
           } in changeset.errors

    snapshot = Workflows.Snapshot.get_current_for(workflow)

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

    for original_edge <- workflow.edges do
      assert snapshot_edge =
               snapshot.edges |> Enum.find(&(&1.id == original_edge.id)),
             "edge not found in snapshot: #{inspect(original_edge)}"

      assert_edge_equal(snapshot_edge, original_edge)
    end
  end

  describe "get_all_for/1" do
    test "by workflow" do
      workflow = insert(:simple_workflow)

      {:ok, snapshot} = Workflows.Snapshot.create(workflow)

      assert [snapshot] == Workflows.Snapshot.get_all_for(workflow)
    end
  end

  describe "get_current_for/1" do
    test "by workflow" do
      initial_workflow = insert(:simple_workflow)

      {:ok, _} = Workflows.Snapshot.create(initial_workflow)

      updated_workflow =
        initial_workflow
        |> Workflows.change_workflow(%{name: "new name"})
        |> Repo.update!()

      {:ok, snapshot} = Workflows.Snapshot.create(updated_workflow)

      # Ensure that the snapshot is the latest one, despite initial_workflow
      # having a `lock_version` of 0.
      assert snapshot == Workflows.Snapshot.get_current_for(initial_workflow)
    end
  end

  describe "get_or_create_latest_for" do
    test "without a workflow" do
      workflow = build(:simple_workflow, id: Ecto.UUID.generate())

      {:error, :no_workflow} =
        Workflows.Snapshot.get_or_create_latest_for(workflow)
    end

    test "without an existing snapshot" do
      workflow = insert(:simple_workflow)

      assert {:ok, snapshot} =
               Workflows.Snapshot.get_or_create_latest_for(workflow)

      assert snapshot == Workflows.Snapshot.get_current_for(workflow)
    end

    test "with an existing snapshot" do
      workflow = insert(:simple_workflow)

      {:ok, existing} = Workflows.Snapshot.get_or_create_latest_for(workflow)
      {:ok, latest} = Workflows.Snapshot.get_or_create_latest_for(workflow)
      assert existing == latest
    end
  end

  defp assert_edge_equal(snapshot, original) do
    assert only_fields(snapshot) ==
             Map.take(original, [
               :id,
               :source_trigger_id,
               :source_job_id,
               :target_job_id,
               :condition_type,
               :condition_expression,
               :condition_label,
               :enabled,
               :inserted_at,
               :updated_at
             ])
  end

  defp assert_job_equal(snapshot, original) do
    assert only_fields(snapshot) ==
             Map.take(original, [
               :id,
               :name,
               :body,
               :adaptor,
               :project_credential_id,
               :inserted_at,
               :updated_at
             ])
  end

  defp only_fields(model) do
    model.__struct__.__schema__(:fields)
    |> Enum.into(%{}, fn field ->
      {field, model |> Map.get(field)}
    end)
  end
end
