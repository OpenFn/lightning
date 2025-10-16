defmodule Lightning.Repo.Migrations.AddLastTotpAtToUserTotp do
  use Ecto.Migration

  def change do
    alter table(:user_totps) do
      add :last_totp_at, :utc_datetime_usec, null: true, default: nil
    end
  end
end
