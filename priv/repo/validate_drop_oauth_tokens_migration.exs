# priv/repo/validate_drop_oauth_tokens_migration.exs
# Script to validate the DROP oauth_tokens table migration
#
# This script validates that the migration which:
# - Moves OAuth token data from oauth_tokens.body to credential_bodies.body
# - Links credentials directly to oauth_clients (removes oauth_tokens middle table)
# - Sets default environment for root projects
# - Drops oauth_tokens table and obsolete columns
#
# Run BEFORE migration:
#     mix run priv/repo/validate_drop_oauth_tokens_migration.exs before
#
# Run AFTER migration:
#     mix run priv/repo/validate_drop_oauth_tokens_migration.exs after
#
# The validator checks:
# - Schema changes (tables/columns dropped)
# - Data integrity (all credentials have bodies)
# - OAuth token fields (access_token, refresh_token, scopes, expiry)
# - OAuth client linking (all OAuth credentials have oauth_client_id)
# - Project environments (root projects have env set)

case System.argv() do
  ["before"] ->
    Lightning.Credentials.DropOauthTokensValidator.validate_before()

  ["after"] ->
    Lightning.Credentials.DropOauthTokensValidator.validate_after()

  _ ->
    IO.puts("""
    Usage: mix run priv/repo/validate_drop_oauth_tokens_migration.exs [before|after]

    Options:
      before  - Validate state BEFORE running migration
      after   - Validate state AFTER running migration
    """)

    System.halt(1)
end
