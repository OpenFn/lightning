defmodule Lightning.Repo.Migrations.CreateCredentialBodies do
  use Ecto.Migration

  def change do
    create table(:credential_bodies, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :credential_id, references(:credentials, type: :binary_id, on_delete: :delete_all),
        null: false

      add :name, :string, null: false
      add :body, :binary, null: false

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:credential_bodies, [:credential_id, :name])
    create index(:credential_bodies, [:credential_id])
    create index(:credential_bodies, [:name])
  end
end
