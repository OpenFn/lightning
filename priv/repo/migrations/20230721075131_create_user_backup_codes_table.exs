defmodule Lightning.Repo.Migrations.CreateUserBackupCodesTable do
  use Ecto.Migration

  def change do
    create table(:user_backup_codes, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, on_delete: :delete_all, type: :binary_id), null: false
      add :code, :binary, null: false
      add :used_at, :naive_datetime_usec

      timestamps()
    end

    create unique_index(:user_backup_codes, [:user_id, :code])
  end
end
