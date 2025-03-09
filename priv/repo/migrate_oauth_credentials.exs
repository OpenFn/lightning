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
alias Lightning.Credentials.OauthClient

Logger.info("Starting OAuth credentials migration")

# Get all OAuth credentials with non-null body
credentials =
  from(c in Credential,
    where: c.schema == "oauth" and not is_nil(c.body) and is_nil(c.oauth_token_id),
    order_by: [desc: c.updated_at]
  )
  |> Repo.all()

total = length(credentials)
Logger.info("Found #{total} OAuth credentials to migrate")

# Track statistics
stats = %{tokens_created: 0, credentials_updated: 0}

# Helper function to find token with overlapping scopes (using same logic as in Lightning.Credentials)
find_token_with_overlapping_scopes = fn user_id, oauth_client_id, requested_scopes ->
  # Query to get tokens for this user/client combination
  tokens = from(token in OauthToken,
    join: token_client in OauthClient,
    on: token.oauth_client_id == token_client.id,
    join: requested_client in OauthClient,
    on: requested_client.id == ^oauth_client_id,
    where:
      token.user_id == ^user_id and
        token_client.client_id == requested_client.client_id and
        token_client.client_secret == requested_client.client_secret
  )
  |> Repo.all()

  # Convert requested scopes to a set for comparison
  requested_scope_set = MapSet.new(requested_scopes)
  requested_scope_count = MapSet.size(requested_scope_set)

  # Filter tokens with overlapping scopes
  tokens
  |> Enum.filter(fn token ->
    token_scope_set = MapSet.new(token.scopes)
    # Keep only tokens that have at least one scope in common with the requested scopes
    MapSet.intersection(token_scope_set, requested_scope_set) |> MapSet.size() > 0
  end)
  |> Enum.max_by(
    fn token ->
      token_scope_set = MapSet.new(token.scopes)

      matching_scope_count =
        MapSet.intersection(token_scope_set, requested_scope_set)
        |> MapSet.size()

      unrequested_scope_count =
        MapSet.difference(token_scope_set, requested_scope_set)
        |> MapSet.size()

      exact_match? =
        matching_scope_count == requested_scope_count &&
          unrequested_scope_count == 0

      last_updated = DateTime.to_unix(token.updated_at)

      # Sort priority: exact matches first, then by number of matching scopes,
      # then fewer unrequested scopes, and finally by most recently updated
      {if(exact_match?, do: 1, else: 0), matching_scope_count,
       -unrequested_scope_count, last_updated}
    end,
    # Return nil if no tokens match
    fn -> nil end
  )
end

# Helper function to extract apiVersion from credential body
extract_api_version = fn credential_body ->
  api_version = Map.get(credential_body, "apiVersion")

  if api_version do
    %{"apiVersion" => api_version}
  else
    %{}
  end
end

# Process each credential
results =
  Enum.reduce(credentials, stats, fn credential, stats ->
    Logger.info("Processing credential #{credential.id} with client_id #{credential.oauth_client_id || "nil"}")

    # Extract apiVersion from credential body
    preserved_fields = extract_api_version.(credential.body)

    # Process in a transaction for data integrity
    Repo.transaction(fn ->
      # Extract scopes from credential body
      scopes =
        case OauthToken.extract_scopes(credential.body) do
          {:ok, extracted_scopes} -> extracted_scopes
          :error -> []
        end

      # Find existing token with matching or compatible scopes
      existing_token =
        if credential.oauth_client_id do
          find_token_with_overlapping_scopes.(credential.user_id, credential.oauth_client_id, scopes)
        else
          nil
        end

      # Find existing token or create new one
      {token, updated_stats} =
        if existing_token do
          Logger.info("Found existing token #{existing_token.id} with compatible scopes")
          {existing_token, stats}
        else
          # Create a new token
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

      # Update the credential to reference the token and preserve apiVersion if present
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
