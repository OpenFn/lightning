defmodule Lightning.Repo.Migrations.DropJsonbGinIndexFromDataclips do
  use Ecto.Migration

  def up do
    drop index(:dataclips, [:body])
  end

  def down do
    create index(:dataclips, [:body], concurrently: true, using: :gin)
  end
end
