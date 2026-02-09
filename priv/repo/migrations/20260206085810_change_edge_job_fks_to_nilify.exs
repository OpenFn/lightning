defmodule Lightning.Repo.Migrations.ChangeEdgeJobFksToNilify do
  use Ecto.Migration

  def up do
    # Drop existing FK constraints that use on_delete: :delete_all
    # These cause cascade deletes that race with Ecto's edge updates
    drop constraint(:workflow_edges, "workflow_edges_target_job_id_fkey")
    drop constraint(:workflow_edges, "workflow_edges_source_job_id_fkey")

    # Recreate FK constraints with ON DELETE SET NULL on only the job ID column.
    # We can't use Ecto's :nilify_all because compound FKs (with workflow_id)
    # would nilify workflow_id too, which violates NOT NULL.
    # PostgreSQL 15+ supports partial SET NULL: ON DELETE SET NULL (column).
    execute """
    ALTER TABLE workflow_edges
    ADD CONSTRAINT workflow_edges_target_job_id_fkey
    FOREIGN KEY (target_job_id, workflow_id)
    REFERENCES jobs(id, workflow_id)
    ON DELETE SET NULL (target_job_id)
    """

    execute """
    ALTER TABLE workflow_edges
    ADD CONSTRAINT workflow_edges_source_job_id_fkey
    FOREIGN KEY (source_job_id, workflow_id)
    REFERENCES jobs(id, workflow_id)
    ON DELETE SET NULL (source_job_id)
    """
  end

  def down do
    drop constraint(:workflow_edges, "workflow_edges_target_job_id_fkey")
    drop constraint(:workflow_edges, "workflow_edges_source_job_id_fkey")

    # Clean up any orphaned edges before restoring cascade constraints
    execute """
    DELETE FROM workflow_edges
    WHERE target_job_id IS NULL OR source_job_id IS NULL
    """

    alter table(:workflow_edges) do
      modify :target_job_id,
             references(:jobs,
               on_delete: :delete_all,
               type: :binary_id,
               with: [workflow_id: :workflow_id]
             )

      modify :source_job_id,
             references(:jobs,
               on_delete: :delete_all,
               type: :binary_id,
               with: [workflow_id: :workflow_id]
             )
    end
  end
end
