defmodule Lightning.Repo.Migrations.BackfillGoLiveWorkflowReleases do
  use Ecto.Migration

  require Logger

  # Option A backfill: every existing live workflow gets exactly one v1 go-live
  # release pointing at its current snapshot (the snapshot whose lock_version
  # matches the workflow's), dated to that snapshot so the version history reads
  # sensibly. Draft workflows get nothing: their history starts at their first
  # real go-live. Backfilled releases have no actor and no source project.
  #
  # The SQL lives in public functions so the same statements can be exercised by
  # a test; the migration itself uses only pure SQL and never touches schemas or
  # context code (which drift over time and would break replay of old migrations).
  def up do
    execute(insert_sql())
    execute(fn -> log_live_workflows_without_snapshot(repo()) end)
  end

  def down do
    execute(delete_sql())
  end

  @doc false
  # Guarded by NOT EXISTS so a re-run is a no-op rather than a duplicate-key
  # crash. A live workflow with no matching snapshot is intentionally left out
  # here and surfaced by log_live_workflows_without_snapshot/1.
  def insert_sql do
    """
    INSERT INTO workflow_releases (
      id,
      version_number,
      kind,
      workflow_id,
      snapshot_id,
      published_by_id,
      source_project_id,
      inserted_at
    )
    SELECT
      gen_random_uuid(),
      1,
      'go_live',
      w.id,
      s.id,
      NULL,
      NULL,
      s.inserted_at
    FROM workflows w
    JOIN workflow_snapshots s
      ON s.workflow_id = w.id
     AND s.lock_version = w.lock_version
    WHERE w.state = 'live'
      AND w.deleted_at IS NULL
      AND NOT EXISTS (
        SELECT 1 FROM workflow_releases r WHERE r.workflow_id = w.id
      )
    """
  end

  @doc false
  # Only removes the backfilled rows: v1 go-live releases with no actor and no
  # source project. Releases created by real go-lives/promotes are left alone.
  def delete_sql do
    """
    DELETE FROM workflow_releases
    WHERE version_number = 1
      AND kind = 'go_live'
      AND published_by_id IS NULL
      AND source_project_id IS NULL
    """
  end

  @doc false
  def live_without_snapshot_sql do
    """
    SELECT w.id
    FROM workflows w
    WHERE w.state = 'live'
      AND w.deleted_at IS NULL
      AND NOT EXISTS (
        SELECT 1 FROM workflow_snapshots s
        WHERE s.workflow_id = w.id
          AND s.lock_version = w.lock_version
      )
    """
  end

  defp log_live_workflows_without_snapshot(repo) do
    %{rows: rows} = repo.query!(live_without_snapshot_sql())

    for [workflow_id] <- rows do
      Logger.warning(
        "Skipping go-live release backfill for live workflow " <>
          "#{Ecto.UUID.load!(workflow_id)}: no snapshot at its current lock_version."
      )
    end
  end
end
