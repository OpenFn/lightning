defmodule Lightning.Repo.Migrations.AddDashboardStatsIndexes do
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def change do
    # Composite index for dashboard stats count_steps query
    # Enables efficient lookup of steps by job_id filtered by inserted_at
    # Addresses ~1.7s query time from sequential scan on steps table
    create index(:steps, [:job_id, :inserted_at], concurrently: true)

    # Composite index for dashboard stats count_runs query
    # Enables efficient lookup of runs by work_order_id filtered by inserted_at
    create index(:runs, [:work_order_id, :inserted_at], concurrently: true)
  end
end
