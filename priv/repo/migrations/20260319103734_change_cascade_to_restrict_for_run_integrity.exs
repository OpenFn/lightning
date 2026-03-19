defmodule Lightning.Repo.Migrations.ChangeCascadeToRestrictForRunIntegrity do
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  # Issue #4538: "Run is king" — reference FKs from runs/steps should use
  # RESTRICT so that deleting referenced data (dataclips, users, triggers,
  # jobs) cannot silently destroy audit records.
  #
  # This migration:
  # 1. Changes 4 existing CASCADE constraints to RESTRICT
  # 2. Creates 2 missing FK constraints (starting_trigger_id, starting_job_id)
  #    that were dropped in a 2024 snapshot migration
  # 3. Adds indexes on unindexed FK columns for RESTRICT check performance
  #
  # Uses NOT VALID + VALIDATE CONSTRAINT to avoid full table locks on large
  # tables. The ADD ... NOT VALID is instant (metadata only), and VALIDATE
  # takes only a SHARE UPDATE EXCLUSIVE lock (allows concurrent reads/writes,
  # only blocks DDL and VACUUM).

  def up do
    # --- Phase 0: Check for orphaned references ---
    # starting_trigger_id and starting_job_id had no FK constraint since the
    # 20240405 snapshot migration. If any triggers or jobs were deleted in that
    # window, those runs now hold dangling references that would fail VALIDATE.
    # Nullify them so the constraint can be applied cleanly.

    execute """
    UPDATE runs SET starting_trigger_id = NULL
    WHERE starting_trigger_id IS NOT NULL
      AND starting_trigger_id NOT IN (SELECT id FROM triggers)
    """

    execute """
    UPDATE runs SET starting_job_id = NULL
    WHERE starting_job_id IS NOT NULL
      AND starting_job_id NOT IN (SELECT id FROM jobs)
    """

    # --- Phase 1: Add indexes concurrently (no locks) ---
    # These columns had no indexes. Without them, every DELETE from the
    # referenced table would seq-scan runs to check for RESTRICT violations.
    create_if_not_exists index(:runs, [:created_by_id], concurrently: true)
    create_if_not_exists index(:runs, [:starting_trigger_id], concurrently: true)
    create_if_not_exists index(:runs, [:starting_job_id], concurrently: true)

    # --- Phase 2: Swap existing CASCADE → RESTRICT (NOT VALID) ---
    # For each existing constraint: drop it, re-add as RESTRICT NOT VALID.
    # NOT VALID means no full-table validation scan during ADD — instant.

    # runs.dataclip_id: CASCADE → RESTRICT
    execute "ALTER TABLE runs DROP CONSTRAINT runs_dataclip_id_fkey"

    execute """
    ALTER TABLE runs
      ADD CONSTRAINT runs_dataclip_id_fkey
      FOREIGN KEY (dataclip_id) REFERENCES dataclips(id)
      ON DELETE RESTRICT
      NOT VALID
    """

    # runs.created_by_id: CASCADE → RESTRICT
    execute "ALTER TABLE runs DROP CONSTRAINT runs_created_by_id_fkey"

    execute """
    ALTER TABLE runs
      ADD CONSTRAINT runs_created_by_id_fkey
      FOREIGN KEY (created_by_id) REFERENCES users(id)
      ON DELETE RESTRICT
      NOT VALID
    """

    # steps.input_dataclip_id: CASCADE → RESTRICT
    execute "ALTER TABLE steps DROP CONSTRAINT steps_input_dataclip_id_fkey"

    execute """
    ALTER TABLE steps
      ADD CONSTRAINT steps_input_dataclip_id_fkey
      FOREIGN KEY (input_dataclip_id) REFERENCES dataclips(id)
      ON DELETE RESTRICT
      NOT VALID
    """

    # steps.output_dataclip_id: CASCADE → RESTRICT
    execute "ALTER TABLE steps DROP CONSTRAINT steps_output_dataclip_id_fkey"

    execute """
    ALTER TABLE steps
      ADD CONSTRAINT steps_output_dataclip_id_fkey
      FOREIGN KEY (output_dataclip_id) REFERENCES dataclips(id)
      ON DELETE RESTRICT
      NOT VALID
    """

    # --- Phase 3: Create missing FK constraints (NOT VALID) ---
    # These were dropped by the 20240405131241 snapshot migration.
    # The columns still exist and contain valid data, but have no FK.

    # runs.starting_trigger_id: no constraint → RESTRICT
    execute """
    ALTER TABLE runs
      ADD CONSTRAINT runs_starting_trigger_id_fkey
      FOREIGN KEY (starting_trigger_id) REFERENCES triggers(id)
      ON DELETE RESTRICT
      NOT VALID
    """

    # runs.starting_job_id: no constraint → RESTRICT
    execute """
    ALTER TABLE runs
      ADD CONSTRAINT runs_starting_job_id_fkey
      FOREIGN KEY (starting_job_id) REFERENCES jobs(id)
      ON DELETE RESTRICT
      NOT VALID
    """

    # --- Phase 4: Validate all constraints ---
    # VALIDATE CONSTRAINT takes a SHARE UPDATE EXCLUSIVE lock — it allows
    # concurrent reads and writes, only blocking DDL and VACUUM. It scans
    # existing rows to confirm they satisfy the constraint.

    execute "ALTER TABLE runs VALIDATE CONSTRAINT runs_dataclip_id_fkey"
    execute "ALTER TABLE runs VALIDATE CONSTRAINT runs_created_by_id_fkey"
    execute "ALTER TABLE runs VALIDATE CONSTRAINT runs_starting_trigger_id_fkey"
    execute "ALTER TABLE runs VALIDATE CONSTRAINT runs_starting_job_id_fkey"
    execute "ALTER TABLE steps VALIDATE CONSTRAINT steps_input_dataclip_id_fkey"
    execute "ALTER TABLE steps VALIDATE CONSTRAINT steps_output_dataclip_id_fkey"
  end

  def down do
    # Restore original CASCADE constraints for the 4 that previously existed.
    execute "ALTER TABLE runs DROP CONSTRAINT runs_dataclip_id_fkey"

    execute """
    ALTER TABLE runs
      ADD CONSTRAINT runs_dataclip_id_fkey
      FOREIGN KEY (dataclip_id) REFERENCES dataclips(id)
      ON DELETE CASCADE
    """

    execute "ALTER TABLE runs DROP CONSTRAINT runs_created_by_id_fkey"

    execute """
    ALTER TABLE runs
      ADD CONSTRAINT runs_created_by_id_fkey
      FOREIGN KEY (created_by_id) REFERENCES users(id)
      ON DELETE CASCADE
    """

    execute "ALTER TABLE steps DROP CONSTRAINT steps_input_dataclip_id_fkey"

    execute """
    ALTER TABLE steps
      ADD CONSTRAINT steps_input_dataclip_id_fkey
      FOREIGN KEY (input_dataclip_id) REFERENCES dataclips(id)
      ON DELETE CASCADE
    """

    execute "ALTER TABLE steps DROP CONSTRAINT steps_output_dataclip_id_fkey"

    execute """
    ALTER TABLE steps
      ADD CONSTRAINT steps_output_dataclip_id_fkey
      FOREIGN KEY (output_dataclip_id) REFERENCES dataclips(id)
      ON DELETE CASCADE
    """

    # Drop the 2 constraints that didn't exist before this migration.
    execute "ALTER TABLE runs DROP CONSTRAINT runs_starting_trigger_id_fkey"
    execute "ALTER TABLE runs DROP CONSTRAINT runs_starting_job_id_fkey"

    # Drop the indexes we added (they didn't exist before).
    drop_if_exists index(:runs, [:created_by_id])
    drop_if_exists index(:runs, [:starting_trigger_id])
    drop_if_exists index(:runs, [:starting_job_id])
  end
end
