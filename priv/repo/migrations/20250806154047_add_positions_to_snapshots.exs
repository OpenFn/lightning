defmodule Lightning.Repo.Migrations.AddPositionsToSnapshots do
  use Ecto.Migration

  def change do
    alter table(:workflow_snapshots) do
      add :positions, :map, null: true
    end
  end
end
