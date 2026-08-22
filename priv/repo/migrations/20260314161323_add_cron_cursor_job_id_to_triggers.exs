defmodule Lightning.Repo.Migrations.AddCronCursorJobIdToTriggers do
  use Ecto.Migration

  def up do
    alter table(:triggers) do
      add :cron_cursor_job_id,
          references(:jobs, type: :binary_id, on_delete: :nilify_all),
          null: true
    end

    flush()

    # Backfill existing cron triggers to preserve current behavior:
    # point at the first downstream job so the old per-step lookup is used.
    execute("""
    UPDATE triggers
    SET cron_cursor_job_id = workflow_edges.target_job_id
    FROM workflow_edges
    WHERE workflow_edges.source_trigger_id = triggers.id
      AND triggers.type = 'cron'
    """)
  end

  def down do
    alter table(:triggers) do
      remove :cron_cursor_job_id
    end
  end
end
