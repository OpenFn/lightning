defmodule Lightning.Repo.Migrations.CreateUserIdentities do
  use Ecto.Migration

  def change do
    create table(:user_identities, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :uuid, on_delete: :delete_all), null: false
      add :provider, :string, null: false
      add :uid, :string, null: false
      timestamps()
    end

    create unique_index(:user_identities, [:provider, :uid])
    create index(:user_identities, [:user_id])
  end
end
