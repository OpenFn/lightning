defmodule Lightning.Repo.Migrations.CleanupCredentialSchema do
  use Ecto.Migration

  def up do
    # oauth_client_id already exists from earlier migration, so skip adding it

    # Step 1: Migrate oauth_client_id from oauth_tokens to credentials (only if NULL)
    execute """
    UPDATE credentials c
    SET oauth_client_id = ot.oauth_client_id
    FROM oauth_tokens ot
    WHERE c.oauth_token_id = ot.id
      AND c.oauth_client_id IS NULL
    """

    # Step 2: Drop columns from credentials
    alter table(:credentials) do
      remove :oauth_token_id
      remove :production
      remove :body
    end

    # Step 3: Drop oauth_tokens table
    drop table(:oauth_tokens)
  end

  def down do
    raise "This migration cannot be reversed"
  end
end
