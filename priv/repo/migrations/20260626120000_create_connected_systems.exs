defmodule Lightning.Repo.Migrations.CreateConnectedSystems do
  use Ecto.Migration

  def change do
    create table(:connected_systems, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :type, :string, null: false

      add :created_by_id,
          references(:users, type: :binary_id, on_delete: :nilify_all)

      timestamps(type: :utc_datetime)
    end

    create unique_index(:connected_systems, [:name])
    create index(:connected_systems, [:created_by_id])

    alter table(:credentials) do
      add :connected_system_id,
          references(:connected_systems, type: :binary_id, on_delete: :nilify_all)
    end

    create index(:credentials, [:connected_system_id])
  end
end
