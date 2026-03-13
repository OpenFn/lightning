defmodule Lightning.Repo.Migrations.AddQueueIndexToRuns do
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def change do
    create index(:runs, [:state, :queue, :inserted_at],
             concurrently: true,
             where: "state IN ('available', 'claimed', 'started')"
           )
  end
end
