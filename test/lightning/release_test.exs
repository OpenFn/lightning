defmodule Lightning.ReleaseTest do
  use Lightning.DataCase, async: false

  alias Lightning.Release
  alias Lightning.Workflows.Workflow

  describe "backfill_deleted_workflow_names/1" do
    test "frees the names of soft-deleted workflows that were never renamed" do
      project = insert(:project)
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      # Soft-deleted and never renamed: should be freed to "<name>_del".
      stale =
        insert(:workflow,
          project: project,
          name: "Patient Sync",
          deleted_at: now
        )

      # Collision: "Report_del" is already taken, so "Report" must land on
      # "Report_del1".
      insert(:workflow, project: project, name: "Report_del", deleted_at: now)

      collide =
        insert(:workflow, project: project, name: "Report", deleted_at: now)

      # Untouched: a live workflow, and one whose name is already freed.
      live = insert(:workflow, project: project, name: "Live One")

      freed =
        insert(:workflow, project: project, name: "Old_del", deleted_at: now)

      assert {:ok, 2} = Release.backfill_deleted_workflow_names()

      assert reload_name(stale) == "Patient Sync_del"
      assert reload_name(collide) == "Report_del1"
      assert reload_name(live) == "Live One"
      assert reload_name(freed) == "Old_del"
    end

    test "is idempotent across runs" do
      project = insert(:project)
      now = DateTime.utc_now() |> DateTime.truncate(:second)
      insert(:workflow, project: project, name: "X", deleted_at: now)

      assert {:ok, 1} = Release.backfill_deleted_workflow_names()
      assert {:ok, 0} = Release.backfill_deleted_workflow_names()
    end

    test "dry_run reports the count without renaming" do
      project = insert(:project)
      now = DateTime.utc_now() |> DateTime.truncate(:second)
      workflow = insert(:workflow, project: project, name: "Y", deleted_at: now)

      assert {:ok, 1} = Release.backfill_deleted_workflow_names(dry_run: true)
      assert reload_name(workflow) == "Y"
    end
  end

  defp reload_name(%Workflow{id: id}), do: Repo.get!(Workflow, id).name
end
