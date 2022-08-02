defmodule Lightning.Repo.Migrations.AddCredentialsAudit do
  use Ecto.Migration

  def change do
    create table("credentials_audit", primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :event, :string, null: false
      add :metadata, :map, default: %{}
      add :row_id, references(:credentials, on_delete: :delete_all, type: :binary_id), null: false
      add :actor_id, references(:users, on_delete: :delete_all, type: :binary_id)

      timestamps(updated_at: false)
    end

    create index("credentials_audit", [:row_id])
  end
end
