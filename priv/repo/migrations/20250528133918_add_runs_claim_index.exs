defmodule Lightning.Repo.Migrations.AddRunsClaimIndex do
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def change do
    create index(:runs, [:state, :priority, :inserted_at],
             concurrently: true,
             where: "state IN ('available', 'claimed', 'started')"
           )
  end
end
