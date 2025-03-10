# Script to migrate OAuth credentials to the new token architecture
#
# Run with:
#     mix run priv/repo/migrate_oauth_credentials.exs
#
# This script migrates credentials with schema 'oauth' to use the new oauth_tokens table
# while properly handling encryption/decryption through Lightning.Vault.

require Logger

import Ecto.Query

alias Lightning.Repo
alias Lightning.Credentials
alias Lightning.Credentials.Credential
alias Lightning.Credentials.OauthToken

Logger.info("Starting OAuth credentials migration")

credentials =
  from(c in Credential,
    where: c.schema == "oauth" and not is_nil(c.body) and is_nil(c.oauth_token_id),
    order_by: [desc: c.updated_at]
  )
  |> Repo.all()

total = length(credentials)
Logger.info("Found #{total} OAuth credentials to migrate")

stats = %{tokens_created: 0, credentials_updated: 0}

extract_api_version = fn credential_body ->
  api_version = Map.get(credential_body, "apiVersion")

  if api_version do
    %{"apiVersion" => api_version}
  else
    %{}
  end
end

results =
  Enum.reduce(credentials, stats, fn credential, stats ->
    Logger.info("Processing credential #{credential.id} with client_id #{credential.oauth_client_id || "nil"}")

    preserved_fields = extract_api_version.(credential.body)

    Repo.transaction(fn ->
      scopes =
        case OauthToken.extract_scopes(credential.body) |> dbg() do
          {:ok, extracted_scopes} -> extracted_scopes
          :error -> []
        end

      existing_token =
        if credential.oauth_client_id do
          Credentials.find_token_with_overlapping_scopes(credential.user_id, credential.oauth_client_id, scopes) |> dbg()
        else
          nil
        end

      {token, updated_stats} =
        if existing_token do
          Logger.info("Found existing token #{existing_token.id} with compatible scopes")
          {existing_token, stats}
        else
          case Repo.insert(%OauthToken{} |> OauthToken.changeset(%{
            user_id: credential.user_id,
            oauth_client_id: credential.oauth_client_id,
            body: credential.body,
            scopes: scopes
          })) do
            {:ok, new_token} ->
              Logger.info("Created new token #{new_token.id} for user #{credential.user_id}")
              {new_token, %{stats | tokens_created: stats.tokens_created + 1}}

            {:error, reason} ->
              Logger.error("Failed to create token: #{inspect(reason)}")
              Repo.rollback(reason)
          end
        end

      case Ecto.Changeset.change(credential, %{
        oauth_token_id: token.id,
        body: preserved_fields
      }) |> Repo.update() do
        {:ok, _updated} ->
          api_version_desc = if Map.has_key?(preserved_fields, "apiVersion") do
            " (preserved apiVersion: #{preserved_fields["apiVersion"]})"
          else
            ""
          end

          Logger.info("Updated credential #{credential.id} to reference token #{token.id}#{api_version_desc}")
          %{updated_stats | credentials_updated: updated_stats.credentials_updated + 1}

        {:error, reason} ->
          Logger.error("Failed to update credential #{credential.id}: #{inspect(reason)}")
          Repo.rollback(reason)
      end
    end)
    |> case do
      {:ok, updated_stats} -> updated_stats
      {:error, _reason} -> stats
    end
  end)

Logger.info("Migration completed: Created #{results.tokens_created} tokens, updated #{results.credentials_updated} credentials")
