defmodule Lightning.Repo.Migrations.AddRunsWorkOrderIdStateFinishedAtIndex do
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def change do
    execute(
      """
      CREATE INDEX CONCURRENTLY IF NOT EXISTS runs_work_order_id_state_finished_at_index
      ON runs (work_order_id, state, finished_at DESC)
      """,
      """
      DROP INDEX CONCURRENTLY IF EXISTS runs_work_order_id_state_finished_at_index
      """
    )
  end
end
