defmodule Lightning.Repo.Migrations.MakeCronCursorFkCompound do
  use Ecto.Migration

  # Single-release, rolling-deploy safe: swaps the single-column cron-cursor FK
  # for a same-workflow compound FK (matching edges): add NOT VALID, clean
  # cross-workflow offenders, then VALIDATE.
  #
  # Lock note: the whole migration runs in one transaction (no
  # @disable_ddl_transaction), so the ACCESS EXCLUSIVE lock taken by DROP/ADD is
  # held on `triggers` until commit — including through VALIDATE. The
  # NOT VALID -> VALIDATE split does NOT buy a weaker-lock window here (that only
  # applies across separate transactions); it is kept for explicitness. This is
  # acceptable because `triggers` is small, so the lock is held only briefly. The
  # single transaction is what makes the swap atomic and rolling-deploy-safe (old
  # code never observes a no-/half-constraint state).
  def up do
    # 1. Drop the existing single-column FK (auto-named by the original migration).
    execute """
    ALTER TABLE triggers
      DROP CONSTRAINT triggers_cron_cursor_job_id_fkey
    """

    # 2. Add the compound, same-workflow FK as NOT VALID (cheap; enforced for
    #    new writes immediately). Partial SET NULL nulls ONLY the cursor column,
    #    never workflow_id (PG15+).
    execute """
    ALTER TABLE triggers
      ADD CONSTRAINT triggers_cron_cursor_job_id_fkey
      FOREIGN KEY (cron_cursor_job_id, workflow_id)
      REFERENCES jobs (id, workflow_id)
      ON DELETE SET NULL (cron_cursor_job_id)
      NOT VALID
    """

    # 3. Clean pre-existing cross-workflow offenders before validating, or
    #    VALIDATE would abort on them.
    execute """
    UPDATE triggers t
    SET cron_cursor_job_id = NULL
    FROM jobs j
    WHERE j.id = t.cron_cursor_job_id
      AND j.workflow_id <> t.workflow_id
    """

    # 4. Validate existing rows (the table is already ACCESS EXCLUSIVE from the
    #    DROP/ADD above — see the lock note in the moduledoc).
    execute """
    ALTER TABLE triggers
      VALIDATE CONSTRAINT triggers_cron_cursor_job_id_fkey
    """
  end

  def down do
    # Revert to the original single-column FK. Note: rows nilified by step 3 of
    # `up` are NOT restored — that data loss is irreversible (see §8).
    execute """
    ALTER TABLE triggers
      DROP CONSTRAINT triggers_cron_cursor_job_id_fkey
    """

    execute """
    ALTER TABLE triggers
      ADD CONSTRAINT triggers_cron_cursor_job_id_fkey
      FOREIGN KEY (cron_cursor_job_id)
      REFERENCES jobs (id)
      ON DELETE SET NULL
    """
  end
end
