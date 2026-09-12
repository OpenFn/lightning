defmodule Lightning.Repo.Migrations.AddWorkflowLifecycleAndReleases do
  use Ecto.Migration

  require Logger

  @moduledoc """
  The workflow lifecycle and its publish trail, in one transaction.

  A workflow gains a `state` of draft or live, backfilled from whether any of
  its triggers is already enabled, so nothing changes about what is running.
  Every workflow that lands live then gets a single v1 go-live release pointing
  at its current snapshot, so a workflow that has been running for months opens
  its version list with a history rather than a blank.

  One migration rather than four, because a half-applied lifecycle is worse
  than none: a `state` column with no releases table, or a releases table with
  nothing in it, are both states nothing in the app expects. The backfill is
  small enough to belong in the same transaction as the schema it fills.

  The SQL lives in public functions so a test can exercise the same statements,
  and the migration touches only SQL, never schemas or context code, which
  drift over time and would break replay.
  """

  def up do
    alter table(:workflows) do
      add :state, :string, null: false, default: "draft"
    end

    # Current behaviour, written down: a workflow with an enabled trigger is
    # already live in every sense that matters.
    execute("""
    UPDATE workflows
       SET state = 'live'
     WHERE id IN (SELECT DISTINCT workflow_id FROM triggers WHERE enabled = true)
    """)

    create table(:workflow_releases, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :version_number, :integer, null: false
      add :kind, :string, null: false

      add :workflow_id,
          references(:workflows, type: :binary_id, on_delete: :delete_all),
          null: false

      # A release must always resolve to real content, so its snapshot is never
      # allowed to disappear out from under it.
      add :snapshot_id,
          references(:workflow_snapshots, type: :binary_id, on_delete: :restrict),
          null: false

      # Null for backfilled go-live releases (no known actor).
      add :published_by_id,
          references(:users, type: :binary_id, on_delete: :nilify_all),
          null: true

      # The sandbox a promote came from; null for a go-live.
      add :source_project_id,
          references(:projects, type: :binary_id, on_delete: :nilify_all),
          null: true

      # Which version a restore put back. Only a :restore release sets it, so
      # the trail reads forward and the version it came from stays in history.
      add :restored_from_version_number, :integer

      timestamps(type: :utc_datetime_usec, updated_at: false, null: false)
    end

    create unique_index(:workflow_releases, [:workflow_id, :version_number])
    create index(:workflow_releases, [:snapshot_id])
    create index(:workflow_releases, [:published_by_id])
    create index(:workflow_releases, [:source_project_id])

    execute(insert_sql())
    execute(fn -> log_live_workflows_without_snapshot(repo()) end)
  end

  def down do
    drop table(:workflow_releases)

    alter table(:workflows) do
      remove :state
    end
  end

  @doc false
  # Every live workflow gets exactly one v1 go-live release at the snapshot
  # whose lock_version matches its own, dated to that snapshot so the history
  # reads sensibly. Drafts get nothing: their history starts at their first real
  # go-live.
  #
  # Guarded by NOT EXISTS so a re-run is a no-op rather than a duplicate-key
  # crash. A live workflow with no matching snapshot is left out and surfaced by
  # log_live_workflows_without_snapshot/1. At most one snapshot can match, since
  # workflow_snapshots carries a unique index on (workflow_id, lock_version).
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
