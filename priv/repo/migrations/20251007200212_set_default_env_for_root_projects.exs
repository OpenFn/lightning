defmodule Lightning.Repo.Migrations.SetDefaultEnvForRootProjects do
  use Ecto.Migration

  def up do
    execute """
    UPDATE projects
    SET env = 'main'
    WHERE parent_id IS NULL
      AND env IS NULL
    """
  end

  def down do
    execute """
    UPDATE projects
    SET env = NULL
    WHERE parent_id IS NULL
      AND env = 'main'
    """
  end
end
