defmodule Lightning.Repo.Migrations.AddLastTotpAtToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :last_totp_at, :utc_datetime_usec, null: true, default: nil
    end
  end
end
