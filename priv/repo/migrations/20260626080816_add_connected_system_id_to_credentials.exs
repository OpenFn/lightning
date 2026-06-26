defmodule Lightning.Repo.Migrations.AddConnectedSystemIdToCredentials do
  use Ecto.Migration

  def change do
    alter table(:credentials) do
      add :connected_system_id,
          references(:connected_systems,
            type: :binary_id,
            on_delete: :nilify_all
          )
    end

    create index(:credentials, [:connected_system_id])
  end
end
