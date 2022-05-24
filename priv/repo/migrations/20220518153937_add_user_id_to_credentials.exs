defmodule Lightning.Repo.Migrations.AddUserIdToCredentials do
  use Ecto.Migration

  def change do
    alter table("credentials") do
      add :user_id, references(:users, on_delete: :nothing, type: :binary_id)
    end

    create index(:credentials, [:user_id])
  end
end
