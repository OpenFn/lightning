defmodule Lightning.Repo.Migrations.AddLastRefreshedToOauthTokens do
  use Ecto.Migration

  def change do
    alter table(:oauth_tokens) do
      add :last_refreshed, :utc_datetime
    end

    execute """
    UPDATE oauth_tokens
    SET last_refreshed = inserted_at
    WHERE last_refreshed IS NULL
    """
  end
end
