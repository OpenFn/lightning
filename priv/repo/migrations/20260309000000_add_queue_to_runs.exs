defmodule Lightning.Repo.Migrations.AddQueueToRuns do
  use Ecto.Migration

  def change do
    alter table(:runs) do
      add :queue, :string, null: false, default: "default"
    end
  end
end
