defmodule Lightning.Repo.Migrations.UpdateWorkflowVersionHistoryConstraint do
  use Ecto.Migration

  def up do
    execute """
    ALTER TABLE workflows
    DROP CONSTRAINT IF EXISTS workflows_version_history_all_hex12;
    """

    execute """
    ALTER TABLE workflows
    ADD CONSTRAINT workflows_version_history_source_hash_format
    CHECK (
      version_history IS NULL OR
      array_length(version_history, 1) IS NULL OR
      array_to_string(version_history, '|') ~ '^(app|cli):[a-f0-9]{12}(\\|(app|cli):[a-f0-9]{12})*$'
    );
    """
  end

  def down do
    execute """
    ALTER TABLE workflows
    DROP CONSTRAINT IF EXISTS workflows_version_history_source_hash_format;
    """

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
