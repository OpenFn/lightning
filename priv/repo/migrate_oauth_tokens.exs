# File: priv/repo/migrate_oauth_tokens.exs
#
# Usage: mix run priv/repo/migrate_oauth_tokens.exs
#
# This script migrates OAuth credential bodies to the new oauth_tokens structure,
# then updates credentials to reference these tokens instead of storing the body directly.

# Make sure the application is started
Mix.Task.run("app.start")

alias Lightning.Repo
alias Lightning.Credentials.{Credential, OauthToken}
import Ecto.Query

IO.puts("Starting OAuth token migration...")

# 1. Find all OAuth credentials with body data
credentials =
  from(c in Credential,
    where: c.schema == "oauth",
    where: not is_nil(c.body),
    order_by: [desc: c.updated_at]
  )
  |> Repo.all()
  |> Repo.preload(:user)

IO.puts("Found #{length(credentials)} OAuth credentials to migrate")

# 2. Group credentials by user_id, oauth_client_id, and scope set
credentials_by_key =
  Enum.group_by(credentials, fn cred ->
    # Extract scopes from credential body
    scopes = case cred.body do
      %{"scope" => scope} when is_binary(scope) -> String.split(scope, " ")
      %{"scopes" => scopes} when is_list(scopes) -> scopes
      _ -> []
    end

    {cred.user_id, cred.oauth_client_id, Enum.sort(scopes)}
  end)

IO.puts("Grouped into #{map_size(credentials_by_key)} unique token groups")

# 3. Create tokens and update credentials
tokens_created = 0
credentials_updated = 0

Enum.each(credentials_by_key, fn {{user_id, oauth_client_id, scopes}, creds} ->
  IO.puts("Processing group: User #{user_id}, Client #{oauth_client_id}, #{length(scopes)} scopes")

  # Get the most recent credential in the group
  most_recent_cred = List.first(creds)

  # Create a new OAuth token
  token_attrs = %{
    user_id: user_id,
    oauth_client_id: oauth_client_id,
    body: most_recent_cred.body,
    scopes: scopes
  }

  case Repo.insert(%OauthToken{} |> OauthToken.changeset(token_attrs)) do
    {:ok, token} ->
      tokens_created = tokens_created + 1
      IO.puts("  Created token #{token.id}")

      # Update all credentials in the group to reference this token
      cred_ids = Enum.map(creds, & &1.id)

      {updated_count, _} =
        from(c in Credential, where: c.id in ^cred_ids)
        |> Repo.update_all(set: [
          oauth_token_id: token.id,
          body: nil,
          updated_at: NaiveDateTime.utc_now()
        ])

      credentials_updated = credentials_updated + updated_count
      IO.puts("  Updated #{updated_count} credentials to reference token #{token.id}")

    {:error, changeset} ->
      IO.puts("  Error creating token: #{inspect(changeset.errors)}")
  end
end)

IO.puts("\nMigration completed:")
IO.puts("- Created #{tokens_created} OAuth tokens")
IO.puts("- Updated #{credentials_updated} credentials")

# 4. Final verification
nil_body_count =
  from(c in Credential,
    where: c.schema == "oauth",
    where: is_nil(c.body),
    where: not is_nil(c.oauth_token_id)
  )
  |> Repo.aggregate(:count)

with_body_count =
  from(c in Credential,
    where: c.schema == "oauth",
    where: not is_nil(c.body)
  )
  |> Repo.aggregate(:count)

IO.puts("\nVerification:")
IO.puts("- #{nil_body_count} credentials now reference tokens (body cleared)")
IO.puts("- #{with_body_count} credentials still have body data (should be 0 if fully migrated)")

# At the end of the script, after verification

if with_body_count > 0 do
  IO.puts("\n⚠️ Warning: Some credentials still have body data and were not migrated!")
else
  IO.puts("\n✅ Success: All OAuth credentials have been migrated to the new token structure")

  IO.puts("\nRemoving oauth_client_id column from credentials table...")

  # Execute the ALTER TABLE command directly using Repo.query
  case Repo.query("ALTER TABLE credentials DROP COLUMN oauth_client_id") do
    {:ok, _} ->
      IO.puts("✅ Successfully removed oauth_client_id column from credentials table")

    {:error, error} ->
      IO.puts("❌ Error removing oauth_client_id column: #{inspect(error)}")
      IO.puts("You will need to manually run a migration to remove this column")
  end
end
