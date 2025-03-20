# Script to migrate OAuth credentials to the new token architecture
#
# Run with:
#     mix run priv/repo/migrate_oauth_credentials.exs
#
# This script migrates credentials with schema 'oauth' to use the new oauth_tokens table
# while properly handling encryption/decryption through Lightning.Vault.

Lightning.Credentials.OauthMigration.run()
