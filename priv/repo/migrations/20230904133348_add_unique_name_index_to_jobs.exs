defmodule Lightning.Repo.Migrations.AddUniqueNameIndexToJobs do
  use Ecto.Migration

  def change do
    create unique_index(:jobs, [:name, :workflow_id])
  end
end
