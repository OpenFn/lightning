defmodule Lightning.Repo.Migrations.RemoveVersionHistoryFromWorkflows do
  use Ecto.Migration

  def up do
    execute """
    ALTER TABLE workflows
    DROP CONSTRAINT IF EXISTS workflows_version_history_source_hash_format;
    """

    alter table(:workflows) do
      remove :version_history
    end
  end

  def down do
    alter table(:workflows) do
      add :version_history, {:array, :string}, default: [], null: false
    end

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
end
