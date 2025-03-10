defmodule Lightning.Credentials.OauthMigration do
  @moduledoc """
  Module to migrate OAuth credentials to the new token architecture.

  This module handles the migration of credentials with schema 'oauth' to use the new oauth_tokens table
  while properly handling encryption/decryption through Lightning.Vault.
  """

  import Ecto.Query

  alias Lightning.Credentials
  alias Lightning.Credentials.Credential
  alias Lightning.Credentials.OauthToken
  alias Lightning.Repo

  require Logger

  @doc """
  Runs the OAuth credentials migration.

  Returns a map with statistics about the migration:
  - `:tokens_created` - Number of new OAuth tokens created
  - `:credentials_updated` - Number of credentials updated to reference tokens
  """
  def run do
    Logger.info("Starting OAuth credentials migration")

    credentials = fetch_unmigrated_credentials()
    total = length(credentials)

    Logger.info("Found #{total} OAuth credentials to migrate")

    stats = %{tokens_created: 0, credentials_updated: 0}
    results = Enum.reduce(credentials, stats, &process_credential/2)

    Logger.info(
      "Migration completed: Created #{results.tokens_created} tokens, updated #{results.credentials_updated} credentials"
    )

    results
  end

  defp fetch_unmigrated_credentials do
    from(c in Credential,
      where:
        c.schema == "oauth" and not is_nil(c.body) and is_nil(c.oauth_token_id),
      order_by: [desc: c.updated_at]
    )
    |> Repo.all()
  end

  defp process_credential(credential, stats) do
    Logger.info(
      "Processing credential #{credential.id} with client_id #{credential.oauth_client_id || "nil"}"
    )

    preserved_fields = extract_api_version(credential.body)

    Repo.transaction(fn ->
      scopes = extract_scopes(credential.body)

      existing_token =
        Credentials.find_best_matching_token_for_scopes(
          credential.user_id,
          credential.oauth_client_id,
          scopes
        )

      {token, updated_stats} =
        if existing_token do
          Logger.info(
            "Found existing token #{existing_token.id} with compatible scopes"
          )

          {existing_token, stats}
        else
          create_new_token(credential, stats)
        end

      update_credential(credential, token, preserved_fields, updated_stats)
    end)
    |> case do
      {:ok, updated_stats} -> updated_stats
      {:error, _reason} -> stats
    end
  end

  defp extract_api_version(credential_body) do
    api_version = Map.get(credential_body, "apiVersion")

    if api_version do
      %{"apiVersion" => api_version}
    else
      %{}
    end
  end

  defp extract_scopes(credential_body) do
    case OauthToken.extract_scopes(credential_body) do
      {:ok, extracted_scopes} -> extracted_scopes
      :error -> []
    end
  end

  defp create_new_token(credential, stats) do
    case Repo.insert(
           %OauthToken{}
           |> OauthToken.changeset(%{
             user_id: credential.user_id,
             oauth_client_id: credential.oauth_client_id,
             body: credential.body,
             scopes: extract_scopes(credential.body)
           })
         ) do
      {:ok, new_token} ->
        Logger.info(
          "Created new token #{new_token.id} for user #{credential.user_id}"
        )

        {new_token, %{stats | tokens_created: stats.tokens_created + 1}}

      {:error, reason} ->
        Logger.error("Failed to create token: #{inspect(reason)}")
        Repo.rollback(reason)
    end
  end

  defp update_credential(credential, token, preserved_fields, stats) do
    case Ecto.Changeset.change(credential, %{
           oauth_token_id: token.id,
           body: preserved_fields
         })
         |> Repo.update() do
      {:ok, _updated} ->
        api_version_desc =
          if Map.has_key?(preserved_fields, "apiVersion") do
            " (preserved apiVersion: #{preserved_fields["apiVersion"]})"
          else
            ""
          end

        Logger.info(
          "Updated credential #{credential.id} to reference token #{token.id}#{api_version_desc}"
        )

        %{stats | credentials_updated: stats.credentials_updated + 1}

      {:error, reason} ->
        Logger.error(
          "Failed to update credential #{credential.id}: #{inspect(reason)}"
        )

        Repo.rollback(reason)
    end
  end
end
