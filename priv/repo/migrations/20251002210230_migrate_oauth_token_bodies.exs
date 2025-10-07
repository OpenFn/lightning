defmodule Lightning.Repo.Migrations.MigrateOauthTokenBodies do
  use Ecto.Migration

  def up do
    execute """
    UPDATE credential_bodies cb
    SET body = ot.body
    FROM oauth_tokens ot
    JOIN credentials c ON c.oauth_token_id = ot.id
    WHERE cb.credential_id = c.id
      AND cb.name = 'main'
      AND c.schema = 'oauth'
    """
  end

  def down do
    raise "This migration cannot be reversed"
  end
end
