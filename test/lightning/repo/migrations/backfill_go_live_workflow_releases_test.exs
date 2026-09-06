defmodule Lightning.Repo.Migrations.BackfillGoLiveWorkflowReleasesTest do
  @moduledoc """
  Exercises the pure-SQL backfill statements against seeded data. The migration
  itself is already applied to the test DB, so we run its exposed SQL directly
  rather than through the migrator.
  """
  use Lightning.DataCase, async: true

  import Lightning.Factories

  # Migrations under priv/repo/migrations are not on the compile path for
  # `mix test`, so load the module before referencing its SQL helpers.
  Code.require_file(
    "priv/repo/migrations/20260721184703_backfill_go_live_workflow_releases.exs"
  )

  alias Lightning.Repo.Migrations.BackfillGoLiveWorkflowReleases, as: Backfill
  alias Lightning.Workflows.WorkflowRelease
  alias Lightning.Workflows.WorkflowReleases

  test "gives each live workflow one v1 go-live release at its current snapshot; drafts get none" do
    snapshot_date = ~U[2024-03-01 12:00:00.000000Z]

    live = insert(:workflow, state: :live, lock_version: 3)

    live_snapshot =
      insert(:snapshot,
        workflow: live,
        lock_version: 3,
        inserted_at: snapshot_date
      )

    draft = insert(:workflow, state: :draft, lock_version: 1)
    insert(:snapshot, workflow: draft, lock_version: 1)

    Repo.query!(Backfill.insert_sql())

    assert [
             %WorkflowRelease{
               version_number: 1,
               kind: :go_live,
               snapshot_id: snapshot_id,
               published_by_id: nil,
               source_project_id: nil,
               inserted_at: inserted_at
             }
           ] = WorkflowReleases.list_for_workflow(live.id)

    assert snapshot_id == live_snapshot.id
    assert inserted_at == snapshot_date

    assert WorkflowReleases.list_for_workflow(draft.id) == []
  end

  test "is safe to run more than once" do
    live = insert(:workflow, state: :live, lock_version: 1)
    insert(:snapshot, workflow: live, lock_version: 1)

    Repo.query!(Backfill.insert_sql())
    Repo.query!(Backfill.insert_sql())

    assert [%WorkflowRelease{version_number: 1}] =
             WorkflowReleases.list_for_workflow(live.id)
  end

  test "skips a live workflow with no snapshot at its current lock_version" do
    live = insert(:workflow, state: :live, lock_version: 2)
    # Snapshot exists but at a stale lock_version, so it is not the current one.
    insert(:snapshot, workflow: live, lock_version: 1)

    Repo.query!(Backfill.insert_sql())

    assert WorkflowReleases.list_for_workflow(live.id) == []

    %{rows: rows} = Repo.query!(Backfill.live_without_snapshot_sql())
    assert Enum.any?(rows, fn [id] -> Ecto.UUID.load!(id) == live.id end)
  end
end
