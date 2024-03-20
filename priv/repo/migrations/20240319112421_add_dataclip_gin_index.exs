defmodule Lightning.Repo.Migrations.AddDataclipGinIndex do
  use Ecto.Migration
  @disable_ddl_transaction true
  @disable_migration_lock true

  def change do
    create index(:dataclips, [:body], concurrently: true, using: :gin)
  end
end
