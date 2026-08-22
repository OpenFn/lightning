defmodule Lightning.Repo.Migrations.ChangeCascadeToRestrictForRunIntegrity do
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  # Issue #4538: "Run is king" — reference FKs from runs/steps should use
  # RESTRICT so that deleting referenced data (dataclips, users) cannot
  # silently destroy audit records.
  #
  # starting_job_id and starting_trigger_id are intentionally left as bare
  # UUID columns (no FK constraint). The snapshot system preserves the full
  # job/trigger data for every run, so the live rows can be freely deleted
  # from workflows without affecting audit history.
  #
  # This migration:
  # 1. Changes 4 existing CASCADE constraints to RESTRICT
  # 2. Adds indexes on unindexed FK columns for query performance
  #
  # Uses NOT VALID + VALIDATE CONSTRAINT to avoid full table locks on large
  # tables. The ADD ... NOT VALID is instant (metadata only), and VALIDATE
  # takes only a SHARE UPDATE EXCLUSIVE lock (allows concurrent reads/writes,
  # only blocks DDL and VACUUM).

  def up do
    # --- Phase 1: Add indexes concurrently (no locks) ---
    # created_by_id needs an index for RESTRICT check performance.
    # starting_trigger_id and starting_job_id get indexes for query
    # performance (no FK, but frequently used in lookups).
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

    # --- Phase 3: Validate all constraints ---
    # VALIDATE CONSTRAINT takes a SHARE UPDATE EXCLUSIVE lock — it allows
    # concurrent reads and writes, only blocking DDL and VACUUM. It scans
    # existing rows to confirm they satisfy the constraint.

    execute "ALTER TABLE runs VALIDATE CONSTRAINT runs_dataclip_id_fkey"
    execute "ALTER TABLE runs VALIDATE CONSTRAINT runs_created_by_id_fkey"
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

    # Drop the indexes we added (they didn't exist before).
    drop_if_exists index(:runs, [:created_by_id])
    drop_if_exists index(:runs, [:starting_trigger_id])
    drop_if_exists index(:runs, [:starting_job_id])
  end
end
