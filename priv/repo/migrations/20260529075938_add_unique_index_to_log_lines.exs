defmodule Lightning.Repo.Migrations.AddUniqueIndexToLogLines do
  use Ecto.Migration

  # log_lines is HASH-partitioned by run_id, so its unique index must include
  # the partition key. (id, run_id) backs the ON CONFLICT used to make run:log
  # and run:batch_logs idempotent. Existing ids are UUIDs generated per-insert,
  # so no dedupe is needed before building the index.
  def change do
    create unique_index(:log_lines, [:id, :run_id])
  end
end
