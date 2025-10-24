defmodule Lightning.Repo.Migrations.BackfillProjectEnvField do
  use Ecto.Migration

  def up do
    execute """
    UPDATE projects
    SET env = 'main'
    WHERE parent_id IS NULL AND env IS NULL
    """
  end

  def down do
    # No-op: We don't want to remove the env values on rollback
    # as they may have been set manually or by the application
    :ok
  end
end
