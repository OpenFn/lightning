defmodule Lightning.Repo.Migrations.CreateWebhookAuthMethodsTable do
  use Ecto.Migration

  def change do
    create table(:webhook_auth_methods, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string
      add :auth_type, :string
      add :username, :binary, null: true
      add :password, :binary, null: true
      add :api_key, :binary, null: true
      add :project_id, references(:projects, on_delete: :delete_all, type: :binary_id)

      timestamps()
    end

    create unique_index(:webhook_auth_methods, [:name, :project_id])
  end
end
