defmodule Lightning.Repo.Migrations.AddWorkerNameToRuns do
  use Ecto.Migration

  def change do
    alter table(:runs) do
      add :worker_name, :string, null: true
    end
  end
end
