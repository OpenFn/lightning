defmodule Lightning.Repo.Migrations.DropJsonbGinIndexFromDataclips do
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def up do
    drop index(:dataclips, [:body])

    create index(:steps, [:input_dataclip_id])
    create index(:steps, [:output_dataclip_id])
  end

  def down do
    create index(:dataclips, [:body], concurrently: true, using: :gin)
  end
end
