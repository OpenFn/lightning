defmodule Lightning.Repo.Migrations.CreateSignInAttempts do
  use Ecto.Migration

  def change do
    create table("sign_in_attempts", primary_key: false) do
      add :key, :text, primary_key: true
      add :count, :integer, null: false
      add :window_started_at, :utc_datetime_usec, null: false
    end

    create index("sign_in_attempts", [:window_started_at])
  end
end
