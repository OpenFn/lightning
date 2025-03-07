defmodule Lightning.Repo.Migrations.MigrateOauthCredentialsToTokens do
  use Ecto.Migration

  def change do
    execute """
    DO $$
    DECLARE
      cred_record RECORD;
      token_id UUID;
      tokens_created INTEGER := 0;
      credentials_updated INTEGER := 0;
    BEGIN
      -- Process each oauth credential
      FOR cred_record IN
        SELECT
          id,
          user_id,
          oauth_client_id,
          body
        FROM credentials
        WHERE schema = 'oauth'
        AND body IS NOT NULL
        ORDER BY updated_at DESC
      LOOP
        -- Print debug info about the client_id
        RAISE NOTICE 'Processing credential % with client_id %',
          cred_record.id, cred_record.oauth_client_id;

        -- Check if we already created a token for this user/client combination
        SELECT id INTO token_id
        FROM oauth_tokens
        WHERE user_id = cred_record.user_id
        AND ((oauth_client_id = cred_record.oauth_client_id) OR
             (oauth_client_id IS NULL AND cred_record.oauth_client_id IS NULL))
        LIMIT 1;

        -- If no token exists yet, create one
        IF token_id IS NULL THEN
          -- Create the token with explicit oauth_client_id
          INSERT INTO oauth_tokens
            (id, user_id, oauth_client_id, body, scopes, inserted_at, updated_at)
          VALUES
            (gen_random_uuid(), cred_record.user_id, cred_record.oauth_client_id,
             cred_record.body, '{}', NOW(), NOW())
          RETURNING id INTO token_id;

          tokens_created := tokens_created + 1;
          RAISE NOTICE 'Created token % for user % and client %',
            token_id, cred_record.user_id, cred_record.oauth_client_id;
        END IF;

        -- Update the credential to reference the token
        UPDATE credentials
        SET
          oauth_token_id = token_id,
          body = NULL,
          updated_at = NOW()
        WHERE id = cred_record.id;

        credentials_updated := credentials_updated + 1;
      END LOOP;

      RAISE NOTICE 'Migration completed: Created % tokens, updated % credentials',
        tokens_created, credentials_updated;
    END $$;
    """
  end
end
