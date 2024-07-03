defmodule Lightning.Repo.Migrations.AddOptionsToRuns do
  use Ecto.Migration

  def change do
    alter table(:runs) do
      add :options, :map
    end
  end
end
