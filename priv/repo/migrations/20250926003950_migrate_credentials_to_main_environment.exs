defmodule Lightning.Repo.Migrations.MigrateCredentialsToMainEnvironment do
  use Ecto.Migration

  def up do
    execute """
    INSERT INTO credential_bodies (id, credential_id, name, body, inserted_at, updated_at)
    SELECT gen_random_uuid(), id, 'main', body, inserted_at, updated_at
    FROM credentials
    """

    execute """
    UPDATE oauth_tokens
    SET credential_body_id = cb.id
    FROM credential_bodies cb
    JOIN credentials c ON c.id = cb.credential_id
    WHERE oauth_tokens.id = c.oauth_token_id AND cb.name = 'main'
    """
  end

  def down do
    execute "UPDATE oauth_tokens SET credential_body_id = NULL"
    execute "DELETE FROM credential_bodies"
  end
end
