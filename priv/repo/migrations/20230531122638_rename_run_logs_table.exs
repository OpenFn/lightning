defmodule Lightning.Repo.Migrations.RenameRunLogsTable do
  use Ecto.Migration

  def change do
    rename table(:run_logs), to: table(:log_lines)

    # Rename the index
    execute "DROP INDEX IF EXISTS run_logs_run_id_index"
    create index(:log_lines, [:run_id])
  end
end
