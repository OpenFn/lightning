defmodule Lightning.Repo.Migrations.CreateNotificationTable do
  use Ecto.Migration

  def change do
    create table("notifications", primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :event, :string, null: false
      add :metadata, :map, default: %{}
      add :user_id, references(:users, on_delete: :delete_all, type: :binary_id)

      timestamps(updated_at: false)
    end
  end
end
