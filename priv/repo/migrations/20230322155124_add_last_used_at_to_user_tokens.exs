defmodule Lightning.Repo.Migrations.AddLastUsedAtToUserTokens do
  use Ecto.Migration

  def change do
    alter table(:user_tokens) do
      add(:last_used_at, :naive_datetime_usec, null: true)
    end
  end
end
