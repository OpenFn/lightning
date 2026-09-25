defmodule Lightning.Repo.Migrations.CreateServiceAccountAssertions do
  use Ecto.Migration

  def change do
    create table(:service_account_assertions, primary_key: false) do
      add :service_account_id, :string, primary_key: true
      add :jti, :string, primary_key: true
      add :expires_at, :utc_datetime, null: false
    end
  end
end
