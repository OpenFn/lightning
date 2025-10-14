defmodule Lightning.Repo.Migrations.BackfillCredentialAssociationsToSandboxes do
  use Ecto.Migration

  def up do
    # Backfill missing credential associations for sandboxes
    # This handles credentials that were added to parent projects before the
    # automatic propagation feature was implemented.

    execute """
    WITH RECURSIVE workspace_descendants AS (
      -- Start with all projects that have credentials
      SELECT
        p.id as root_id,
        p.id as descendant_id,
        pc.credential_id
      FROM projects p
      JOIN project_credentials pc ON pc.project_id = p.id

      UNION ALL

      -- Recursively get all descendants
      SELECT
        wd.root_id,
        child.id as descendant_id,
        wd.credential_id
      FROM workspace_descendants wd
      JOIN projects child ON child.parent_id = wd.descendant_id
    ),
    missing_associations AS (
      -- Find credentials that should be in sandboxes but aren't
      SELECT DISTINCT
        gen_random_uuid() as id,
        wd.descendant_id as project_id,
        wd.credential_id,
        NOW() as inserted_at,
        NOW() as updated_at
      FROM workspace_descendants wd
      WHERE
        -- Only for actual descendants (not the root itself)
        wd.descendant_id != wd.root_id
        -- And where the association doesn't already exist
        AND NOT EXISTS (
          SELECT 1
          FROM project_credentials pc
          WHERE pc.project_id = wd.descendant_id
            AND pc.credential_id = wd.credential_id
        )
    )
    INSERT INTO project_credentials (id, project_id, credential_id, inserted_at, updated_at)
    SELECT id, project_id, credential_id, inserted_at, updated_at
    FROM missing_associations
    ON CONFLICT (project_id, credential_id) DO NOTHING
    """
  end

  def down do
    # This is a data migration that backfills missing associations.
    # Rolling back would require knowing which associations were added by this
    # migration vs. which were added legitimately by users, which is not feasible.
    # Therefore, this migration is irreversible.
    :ok
  end
end
