defmodule Lightning.Repo.Migrations.AddUniqueNameIndexToJobs do
  use Ecto.Migration

  def up do
    execute """
    CREATE UNIQUE INDEX jobs_name_workflow_id_index ON jobs (LOWER(REPLACE(name, '-', ' ')), workflow_id);
    """
  end

  def down do
    execute """
    DROP INDEX jobs_name_workflow_id_index;
    """
  end
end
