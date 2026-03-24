defmodule Lightning.Repo.Migrations.ReSnapshotCronCursorJobId do
  @moduledoc """
  Creates new snapshots for workflows with cron triggers that have a
  cron_cursor_job_id set.

  The previous migration added cron_cursor_job_id to triggers and backfilled
  it, but existing snapshots were created before that column existed. Since
  runs execute against snapshots, the cron_cursor_job_id was effectively
  invisible at runtime until a new snapshot is captured.
  """
  use Ecto.Migration

  def up do
    # Bump lock_version and updated_at on affected workflows
    execute("""
    UPDATE workflows
    SET lock_version = lock_version + 1,
        updated_at = NOW()
    WHERE id IN (
      SELECT DISTINCT workflow_id
      FROM triggers
      WHERE type = 'cron'
        AND cron_cursor_job_id IS NOT NULL
    )
    """)

    # Create new snapshots for those workflows
    execute("""
    INSERT INTO workflow_snapshots (id, workflow_id, name, lock_version, positions, jobs, triggers, edges, inserted_at)
    SELECT
      gen_random_uuid(),
      w.id,
      w.name,
      w.lock_version,
      w.positions,
      COALESCE(
        (SELECT jsonb_agg(jsonb_build_object(
          'id', j.id,
          'name', j.name,
          'body', j.body,
          'adaptor', j.adaptor,
          'project_credential_id', j.project_credential_id,
          'keychain_credential_id', j.keychain_credential_id,
          'inserted_at', j.inserted_at,
          'updated_at', j.updated_at
        ))
        FROM jobs j WHERE j.workflow_id = w.id),
        '[]'::jsonb
      ),
      COALESCE(
        (SELECT jsonb_agg(jsonb_build_object(
          'id', t.id,
          'comment', t.comment,
          'custom_path', t.custom_path,
          'cron_expression', t.cron_expression,
          'enabled', t.enabled,
          'webhook_reply', t.webhook_reply,
          'type', t.type,
          'cron_cursor_job_id', t.cron_cursor_job_id,
          'kafka_configuration', t.kafka_configuration,
          'inserted_at', t.inserted_at,
          'updated_at', t.updated_at
        ))
        FROM triggers t WHERE t.workflow_id = w.id),
        '[]'::jsonb
      ),
      COALESCE(
        (SELECT jsonb_agg(jsonb_build_object(
          'id', e.id,
          'source_job_id', e.source_job_id,
          'source_trigger_id', e.source_trigger_id,
          'target_job_id', e.target_job_id,
          'condition_type', e.condition_type,
          'condition_expression', e.condition_expression,
          'condition_label', e.condition_label,
          'enabled', e.enabled,
          'inserted_at', e.inserted_at,
          'updated_at', e.updated_at
        ))
        FROM workflow_edges e WHERE e.workflow_id = w.id),
        '[]'::jsonb
      ),
      NOW()
    FROM workflows w
    WHERE w.id IN (
      SELECT DISTINCT workflow_id
      FROM triggers
      WHERE type = 'cron'
        AND cron_cursor_job_id IS NOT NULL
    )
    """)
  end

  def down do
    :ok
  end
end
