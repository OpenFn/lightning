defmodule Lightning.Repo.Migrations.AddStepsJobIdExitReasonFinishedAtIndex do
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def change do
    execute(
      """
      CREATE INDEX CONCURRENTLY IF NOT EXISTS steps_job_id_exit_reason_finished_at_index
      ON steps (job_id, exit_reason, finished_at DESC)
      """,
      """
      DROP INDEX CONCURRENTLY IF EXISTS steps_job_id_exit_reason_finished_at_index
      """
    )
  end
end
