defmodule Lightning.Repo.Migrations.AddQueueToRuns do
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def change do
    alter table(:runs) do
      add :queue, :string, null: false, default: "default"
    end

    create index(:runs, [:state, :queue, :inserted_at],
             concurrently: true,
             where: "state IN ('available', 'claimed', 'started')"
           )
  end
end
