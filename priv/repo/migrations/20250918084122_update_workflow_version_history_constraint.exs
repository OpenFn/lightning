defmodule Lightning.Repo.Migrations.UpdateWorkflowVersionHistoryConstraint do
  use Ecto.Migration

  def up do
    # Remove the existing constraint that only allows hex strings
    execute """
    ALTER TABLE workflows
    DROP CONSTRAINT IF EXISTS workflows_version_history_all_hex12;
    """

    # Add new constraint using array_to_string and regexp
    execute """
    ALTER TABLE workflows
    ADD CONSTRAINT workflows_version_history_source_hash_format
    CHECK (
      version_history IS NULL OR
      array_to_string(version_history, '|') ~ '^((app|cli):[a-f0-9]{12}(\||$))*$'
    );
    """
  end

  def down do
    # Remove the new constraint
    execute """
    ALTER TABLE workflows
    DROP CONSTRAINT IF EXISTS workflows_version_history_source_hash_format;
    """

    # Restore the original constraint (this will fail if data doesn't match)
    execute """
    ALTER TABLE workflows
    ADD CONSTRAINT workflows_version_history_all_hex12
    CHECK (
      version_history IS NULL OR
      array_to_string(version_history, '|') ~ '^([a-f0-9]{12}(\||$))*$'
    );
    """
  end
end
