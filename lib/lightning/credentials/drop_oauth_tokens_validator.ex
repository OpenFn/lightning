defmodule Lightning.Credentials.DropOauthTokensValidator do
  @moduledoc """
  Validates the DropOauthTokensTable migration.

  This module validates that the migration which drops the oauth_tokens table
  and consolidates all credential data into credential_bodies has completed successfully.

  ## What it validates

  ### Schema Changes
  - oauth_tokens table is dropped
  - credentials.body column is removed
  - credentials.oauth_token_id column is removed
  - credentials.production column is removed

  ### Data Integrity
  - All credentials have credential_bodies
  - All OAuth credentials have oauth_client_id set
  - OAuth credential_bodies contain valid token data:
    - access_token
    - refresh_token
    - token_type
    - scope or scopes
    - expires_in or expires_at
  - All root projects have env set to 'main'

  ## Usage

      # Before migration
      Lightning.Credentials.DropOauthTokensValidator.validate_before()

      # After migration
      Lightning.Credentials.DropOauthTokensValidator.validate_after()

  Or use the validation script:

      mix run priv/repo/validate_drop_oauth_tokens_migration.exs before
      mix run priv/repo/validate_drop_oauth_tokens_migration.exs after
  """

  import Ecto.Query
  alias Lightning.Repo
  alias Lightning.Credentials.Credential
  alias Lightning.Credentials.CredentialBody
  alias Lightning.Projects.Project

  def validate_before do
    IO.puts("\n=== BEFORE MIGRATION ===")
    IO.puts("oauth_tokens table exists: #{table_exists?("oauth_tokens")}")
    IO.puts("credentials.body exists: #{column_exists?("credentials", "body")}")

    IO.puts(
      "credentials.oauth_token_id exists: #{column_exists?("credentials", "oauth_token_id")}"
    )

    IO.puts(
      "credentials.production exists: #{column_exists?("credentials", "production")}"
    )

    oauth_count =
      Repo.aggregate(from(c in Credential, where: c.schema == "oauth"), :count)

    IO.puts("OAuth credentials: #{oauth_count}")
  end

  def validate_after do
    IO.puts("\n=== AFTER MIGRATION ===")

    # Check old stuff is gone
    oauth_tokens_exists = table_exists?("oauth_tokens")
    body_exists = column_exists?("credentials", "body")
    oauth_token_id_exists = column_exists?("credentials", "oauth_token_id")
    production_exists = column_exists?("credentials", "production")

    IO.puts("\nSchema Changes:")
    IO.puts("oauth_tokens table exists: #{oauth_tokens_exists}")
    IO.puts("credentials.body exists: #{body_exists}")
    IO.puts("credentials.oauth_token_id exists: #{oauth_token_id_exists}")
    IO.puts("credentials.production exists: #{production_exists}")

    # Check data integrity using Ecto
    total = Repo.aggregate(Credential, :count)

    creds_without_bodies =
      Repo.all(
        from c in Credential,
          left_join: cb in CredentialBody,
          on: cb.credential_id == c.id,
          group_by: c.id,
          having: count(cb.id) == 0,
          select: c.id
      )

    oauth_creds =
      Repo.all(
        from c in Credential,
          where: c.schema == "oauth",
          preload: :credential_bodies
      )

    oauth_total = length(oauth_creds)

    oauth_without_client_id =
      Enum.count(oauth_creds, &is_nil(&1.oauth_client_id))

    # Check OAuth token bodies have all required fields
    oauth_body_issues = check_oauth_token_bodies(oauth_creds)

    root_projects =
      Repo.aggregate(from(p in Project, where: is_nil(p.parent_id)), :count)

    root_without_env =
      Repo.aggregate(
        from(p in Project, where: is_nil(p.parent_id) and is_nil(p.env)),
        :count
      )

    IO.puts("\nData Integrity:")
    IO.puts("Total credentials: #{total}")
    IO.puts("Credentials WITHOUT bodies: #{length(creds_without_bodies)}")
    IO.puts("OAuth credentials: #{oauth_total}")
    IO.puts("OAuth WITHOUT oauth_client_id: #{oauth_without_client_id}")

    IO.puts("\nOAuth Token Body Validation:")

    IO.puts(
      "OAuth WITHOUT access_token: #{oauth_body_issues.missing_access_token}"
    )

    IO.puts(
      "OAuth WITHOUT refresh_token: #{oauth_body_issues.missing_refresh_token}"
    )

    IO.puts("OAuth WITHOUT token_type: #{oauth_body_issues.missing_token_type}")
    IO.puts("OAuth WITHOUT scope/scopes: #{oauth_body_issues.missing_scopes}")

    IO.puts(
      "OAuth WITHOUT expires_in/expires_at: #{oauth_body_issues.missing_expiry}"
    )

    IO.puts("OAuth with invalid/empty body: #{oauth_body_issues.invalid_body}")

    IO.puts("\nProject Environment:")
    IO.puts("Root projects: #{root_projects}")
    IO.puts("Root projects WITHOUT env: #{root_without_env}")

    # Pass/Fail
    all_checks_pass =
      length(creds_without_bodies) == 0 and
        oauth_without_client_id == 0 and
        oauth_body_issues.missing_access_token == 0 and
        oauth_body_issues.missing_refresh_token == 0 and
        oauth_body_issues.missing_token_type == 0 and
        oauth_body_issues.missing_scopes == 0 and
        oauth_body_issues.missing_expiry == 0 and
        oauth_body_issues.invalid_body == 0 and
        root_without_env == 0 and
        not oauth_tokens_exists and
        not body_exists and
        not oauth_token_id_exists and
        not production_exists

    if all_checks_pass do
      IO.puts("\n✅ MIGRATION SUCCESSFUL - All checks passed")
      :ok
    else
      IO.puts("\n❌ MIGRATION FAILED - Check values above")
      :error
    end
  end

  defp check_oauth_token_bodies(oauth_creds) do
    results =
      Enum.reduce(
        oauth_creds,
        %{
          missing_access_token: 0,
          missing_refresh_token: 0,
          missing_token_type: 0,
          missing_scopes: 0,
          missing_expiry: 0,
          invalid_body: 0
        },
        fn cred, acc ->
          main_body = Enum.find(cred.credential_bodies, &(&1.name == "main"))

          cond do
            # No main body or body is not a map
            not main_body || not is_map(main_body.body) ->
              %{acc | invalid_body: acc.invalid_body + 1}

            # Body exists, check required fields
            true ->
              body = main_body.body

              acc
              |> update_if_missing(body, "access_token", :missing_access_token)
              |> update_if_missing(body, "refresh_token", :missing_refresh_token)
              |> update_if_missing(body, "token_type", :missing_token_type)
              |> update_if_missing_scopes(body)
              |> update_if_missing_expiry(body)
          end
        end
      )

    results
  end

  defp update_if_missing(acc, body, field, counter) do
    if Map.has_key?(body, field) and not is_nil(body[field]) do
      acc
    else
      Map.update!(acc, counter, &(&1 + 1))
    end
  end

  defp update_if_missing_scopes(acc, body) do
    has_scopes =
      (Map.has_key?(body, "scope") and not is_nil(body["scope"])) or
        (Map.has_key?(body, "scopes") and not is_nil(body["scopes"]))

    if has_scopes do
      acc
    else
      Map.update!(acc, :missing_scopes, &(&1 + 1))
    end
  end

  defp update_if_missing_expiry(acc, body) do
    has_expiry =
      (Map.has_key?(body, "expires_in") and not is_nil(body["expires_in"])) or
        (Map.has_key?(body, "expires_at") and not is_nil(body["expires_at"]))

    if has_expiry do
      acc
    else
      Map.update!(acc, :missing_expiry, &(&1 + 1))
    end
  end

  defp table_exists?(table) do
    query =
      "SELECT EXISTS (SELECT FROM information_schema.tables WHERE table_schema = 'public' AND table_name = '#{table}')"

    case Repo.query(query) do
      {:ok, %{rows: [[exists]]}} -> exists
      _ -> false
    end
  end

  defp column_exists?(table, column) do
    query =
      "SELECT EXISTS (SELECT FROM information_schema.columns WHERE table_schema = 'public' AND table_name = '#{table}' AND column_name = '#{column}')"

    case Repo.query(query) do
      {:ok, %{rows: [[exists]]}} -> exists
      _ -> false
    end
  end
end
