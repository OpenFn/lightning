defmodule Lightning.Repo.Migrations.CreateUsersTotpsTable do
  use Ecto.Migration

  def change do
    create table(:users_totps, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, on_delete: :delete_all, type: :binary_id), null: false
      add :secret, :binary, null: false

      timestamps()
    end

    create unique_index(:users_totps, [:user_id])

    alter table(:users) do
      add :mfa_enabled, :boolean, default: false
    end
  end
end
