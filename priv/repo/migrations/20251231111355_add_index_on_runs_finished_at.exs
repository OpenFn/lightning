defmodule Lightning.Repo.Migrations.AddIndexOnRunsFinishedAt do
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def change do
    create_if_not_exists index(:runs, [:finished_at], concurrently: true)
  end
end
