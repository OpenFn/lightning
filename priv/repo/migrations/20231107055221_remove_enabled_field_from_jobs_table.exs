defmodule Lightning.Repo.Migrations.RemoveEnabledFieldFromJobsTable do
  use Ecto.Migration

  def change do
    alter table(:jobs) do
      remove :enabled
    end
  end
end
