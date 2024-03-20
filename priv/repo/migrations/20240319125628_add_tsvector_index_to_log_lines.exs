defmodule Lightning.Repo.Migrations.AddTsvectorIndexToLogLines do
  use Ecto.Migration
  @disable_ddl_transaction true
  @disable_migration_lock true

  def change do
    create index(:log_lines, [:search_vector], using: :gin)
  end
end
