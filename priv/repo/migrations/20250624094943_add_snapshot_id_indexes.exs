defmodule Lightning.Repo.Migrations.AddSnapshotIdIndexes do
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def change do
    create index(:runs, [:snapshot_id], concurrently: true)
    create index(:steps, [:snapshot_id], concurrently: true)
  end
end
