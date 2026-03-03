defmodule Lightning.Repo.Migrations.AddRunsInsertedAtBrinIndex do
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def change do
    execute(
      """
      CREATE INDEX CONCURRENTLY IF NOT EXISTS runs_inserted_at_brin_index
      ON runs USING brin (inserted_at)
      """,
      """
      DROP INDEX CONCURRENTLY IF EXISTS runs_inserted_at_brin_index
      """
    )
  end
end
