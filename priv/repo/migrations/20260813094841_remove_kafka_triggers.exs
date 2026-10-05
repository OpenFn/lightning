defmodule Lightning.Repo.Migrations.RemoveKafkaTriggers do
  @moduledoc """
  Removes the Kafka trigger feature.

  Three kinds of data are affected, and each is treated differently on purpose.

  Triggers are converted to disabled webhook triggers rather than deleted.
  Deleting one takes the workflow's entry edge with it, and that leaves the
  workflow unrunnable, its history unretriable, and no way back: the editor has
  no way to add a trigger, and the YAML we export for a triggerless workflow is
  rejected by our own importer. Converting keeps the trigger id, so the edge,
  the work orders and the runs all still resolve, and the owner is left with
  something they can see and change.

  `enabled` is forced false whatever it was before. A Kafka trigger consumed
  from a broker its owner had chosen; a webhook accepts whatever reaches its
  URL. Carrying the flag across that change would hand someone a live public
  endpoint they never asked for.

  Each affected workflow then gets a fresh snapshot at its bumped
  `lock_version`, recording the converted trigger. Runs execute against the
  snapshot whose version matches the workflow's, and nothing creates one on
  demand, so bumping the version without this would refuse every new work order
  and every retry for that workflow until someone saved it by hand.

  Dataclips are left exactly as they are. They are the inputs of historical work
  orders, so deleting them would tear holes in the run history, and relabelling
  them would make each record claim it arrived some other way - a change that
  reads as fact to whoever looks next and cannot be undone. `:kafka` stays a
  known dataclip type for that reason, and those rows are now covered by the
  retention wipe, which had been skipping them.

  Nothing is dropped here. The `kafka_configuration` column and the Kafka
  message dedup table both stay until a later release, so that this one can be
  rolled out without stopping the previous version first: its trigger schema
  still declares that column, so its every trigger read names it, on every
  instance whether or not it ever used Kafka. Deferring the drops leaves this
  migration holding row locks on the converted triggers alone, so inbound
  webhooks are never queued behind it.

  Keeping the column also leaves a way back. `kafka_configuration IS NOT NULL`
  identifies exactly the webhooks that used to be Kafka triggers, so rolling the
  code back and restoring their type is possible until the column goes. `enabled`
  is not recoverable, by choice - see above.

  The credentials therefore stay where they were for now, and they are not the
  only copy in any case. Taking a snapshot copies a trigger's whole
  configuration into `workflow_snapshots`, and the collaborative editor used to
  write the credentials into its shared document, which persists in
  `collaboration_document_states`. Nothing can read either back out - the
  snapshot schema no longer declares the field, so it is dropped on load, and
  neither export path can emit it - but anyone rotating away from those brokers
  should not assume the secrets are gone from the database.

  On the hosted platform there is nothing to remove: no Kafka trigger and no
  Kafka dataclip has ever existed there.
  """
  use Ecto.Migration

  def up do
    # Remember which workflows are affected before the conversion, because
    # afterwards nothing matches type = 'kafka' any more and the snapshot insert
    # below still needs the list.
    execute("""
    CREATE TEMPORARY TABLE kafka_workflow_ids ON COMMIT DROP AS
    SELECT DISTINCT workflow_id AS workflow_id FROM triggers WHERE type = 'kafka'
    """)

    # Bump the workflow before changing its trigger. The collaborative editor
    # decides whether to rebuild its persisted document by comparing
    # lock_version alone; without this it keeps the old trigger in the doc and
    # every later save of that workflow is refused as invalid, with nothing on
    # screen to say why. Migration 20260319155941 does the same for the same
    # reason.
    execute("""
    UPDATE workflows
    SET lock_version = lock_version + 1,
        updated_at = NOW()
    WHERE id IN (SELECT workflow_id FROM kafka_workflow_ids)
    """)

    # Convert rather than delete. Deleting takes the workflow's entry edge with
    # it, which leaves the workflow unrunnable, its history unretriable, and no
    # way back: the editor cannot add a trigger, and the YAML we export for a
    # triggerless workflow is rejected by our own importer. Converting keeps the
    # id, so the edge, the work orders and the runs all still resolve, and the
    # owner is left with something they can see and change.
    #
    # enabled is forced false whatever it was. A Kafka trigger read from a
    # broker the owner chose; a webhook accepts anything that reaches its URL.
    # Carrying an enabled flag across that change would hand someone a live
    # public endpoint they never asked for. Disabled, the URL answers 403 and
    # nothing runs until a person decides it should.
    #
    # kafka_configuration is left in place. The column is dropped in a later
    # release, and until then it marks which webhooks came from here.
    execute("""
    UPDATE triggers
    SET type = 'webhook',
        enabled = false,
        webhook_reply = COALESCE(webhook_reply, 'before_start'),
        updated_at = NOW()
    WHERE type = 'kafka'
    """)

    # The bump above is not enough on its own. Runs execute against the snapshot
    # whose lock_version matches the workflow's, and nothing creates one on
    # demand: with the workflow at N + 1 and its newest snapshot still at N,
    # every new work order and every retry for that workflow fails its changeset
    # with "snapshot is required" until someone saves the workflow by hand. So
    # capture the workflow as it now stands, after the conversion, which is why
    # this runs after it and why the trigger it records reads webhook and
    # disabled.
    #
    # kafka_configuration is deliberately not copied. The snapshot schema no
    # longer declares it, so it would be dropped on load anyway, and there is no
    # reason to write the credentials into a second place on the way out.
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
          'webhook_response_config', t.webhook_response_config,
          'type', t.type,
          'cron_cursor_job_id', t.cron_cursor_job_id,
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
    WHERE w.id IN (SELECT workflow_id FROM kafka_workflow_ids)
    ON CONFLICT (workflow_id, lock_version) DO NOTHING
    """)

    # This release has no such worker, so any of its rows still queued would be
    # dequeued after deploy and discarded as unknown, with no code left to
    # explain the error. oban_jobs has no index on worker, so this scans; it is
    # last because nothing else waits on it.
    execute("""
    DELETE FROM oban_jobs
    WHERE worker = 'Lightning.KafkaTriggers.DuplicateTrackingCleanupWorker'
    """)
  end

  def down do
    raise Ecto.MigrationError,
      message: """
      Converting the Kafka triggers cannot be undone automatically.

      Their type and enabled flag are not recorded anywhere, so there is nothing
      to read them back from. Dataclips and run history are untouched either way.

      While the kafka_configuration column is still there - it is dropped in a
      later release - a manual rollback is possible. Those triggers are exactly:

        SELECT id FROM triggers
        WHERE type = 'webhook' AND kafka_configuration IS NOT NULL

      Roll the application back first, then restore their type. Their enabled
      flag was deliberately forced to false and has to be set by hand.
      """
  end
end
