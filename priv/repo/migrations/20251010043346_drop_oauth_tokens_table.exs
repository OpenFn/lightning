defmodule Lightning.Repo.Migrations.DropOauthTokensTable do
  @moduledoc """
  Consolidates credential storage by moving OAuth token data into credential_bodies
  and removing the separate oauth_tokens table.

  ## Overview

  This migration transforms the credential architecture from:
  - credentials.body (credential config)
  - oauth_tokens.body (OAuth token data)
  - Separate tables for different data types

  To:
  - credential_bodies.body (ALL credential data, including OAuth tokens)
  - Single unified storage model
  - Direct credential → oauth_client linking

  ## What Changes

  1. OAuth token data moves from oauth_tokens.body → credential_bodies.body
  2. OAuth client linking moves from credentials → oauth_tokens → oauth_clients
     to credentials → oauth_clients (direct)
  3. Default environment set for root projects
  4. Old columns and oauth_tokens table deleted

  ## Example: OAuth Credential Transformation

  BEFORE:
    credentials (id: 123, schema: 'oauth', oauth_token_id: 456, body: {...})
    oauth_tokens (id: 456, body: {access_token: 'abc', refresh_token: 'xyz'}, oauth_client_id: 789)
    credential_bodies (credential_id: 123, name: 'main', body: {})

  AFTER:
    credentials (id: 123, schema: 'oauth', oauth_client_id: 789)
    credential_bodies (credential_id: 123, name: 'main', body: {access_token: 'abc', refresh_token: 'xyz'})
    oauth_tokens table → DELETED

  ## Example: Project Environment

  BEFORE:
    projects (id: 1, name: 'My Project', parent_id: NULL, env: NULL)

  AFTER:
    projects (id: 1, name: 'My Project', parent_id: NULL, env: 'main')

  ## Validation

  After running, verify with:
    Lightning.Credentials.MigrationValidator.validate()

  Expected: All credentials have credential_bodies, all OAuth credentials have oauth_client_id
  """

  use Ecto.Migration

  def change do
    # Step 1: Copy OAuth token bodies to credential_bodies
    # For OAuth credentials, REPLACE the credential_body's body with oauth_token's body
    # This moves access_token, refresh_token, etc. into credential_bodies
    execute """
    UPDATE credential_bodies cb
    SET body = ot.body
    FROM oauth_tokens ot
    JOIN credentials c ON c.oauth_token_id = ot.id
    WHERE cb.credential_id = c.id
      AND cb.name = 'main'
      AND c.schema = 'oauth'
    """

    # Step 2: Copy oauth_client_id to credentials
    # Creates direct link: credentials → oauth_clients (bypassing oauth_tokens)
    # Only updates if oauth_client_id is NULL (idempotent)
    execute """
    UPDATE credentials c
    SET oauth_client_id = ot.oauth_client_id
    FROM oauth_tokens ot
    WHERE c.oauth_token_id = ot.id
      AND c.oauth_client_id IS NULL
    """

    # Step 3: Set default env for root projects
    # Root projects (parent_id IS NULL) need env='main' for credential resolution
    # Child projects inherit from parent, so only root projects need this
    execute """
    UPDATE projects
    SET env = 'main'
    WHERE parent_id IS NULL
      AND env IS NULL
    """

    # Step 4: Drop old schema
    # Now that data is consolidated, remove obsolete columns and table
    alter table(:credentials) do
      remove :oauth_token_id
      remove :production
      remove :body
    end

    # Step 5: Drop the oauth_tokens table entirely
    # All token data now in credential_bodies
    drop table(:oauth_tokens)
  end
end
