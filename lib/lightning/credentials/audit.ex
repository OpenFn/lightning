defmodule Lightning.Credentials.Audit do
  @moduledoc """
  Model for storing changes to Credentials
  """
  use Lightning.Auditing.Audit,
    repo: Lightning.Repo,
    item: "credential",
    events: [
      "created",
      "updated",
      "added_to_project",
      "removed_from_project",
      "deleted",
      "transfered",
      "token_refreshed",
      "token_refresh_failed",
      "token_revoked"
    ]

  def update_changes(changes) when is_map(changes) do
    if Map.has_key?(changes, :body) do
      changes
      |> Map.update(:body, nil, fn val ->
        {:ok, val} = Lightning.Encrypted.Map.dump(val)
        Base.encode64(val)
      end)
    else
      changes
    end
  end

  @doc """
  Creates a user-initiated audit event for credential operations.
  """
  def user_initiated_event(event, credential, changes \\ %{}) do
    %{id: id, user: user} = Lightning.Repo.preload(credential, :user)
    event(event, id, user, changes)
  end

  @doc """
  Creates an audit event for OAuth token refresh success.
  Records the refresh operation with metadata about the OAuth client and scopes.
  """
  def oauth_token_refreshed_event(credential, metadata \\ %{}) do
    %{id: id, user: user} = Lightning.Repo.preload(credential, :user)

    # Don't include sensitive token data in audit
    safe_metadata =
      metadata
      |> Map.take([:client_id, :scopes, :expires_in, :token_type])
      |> Map.put(:refreshed_at, DateTime.utc_now())

    event("token_refreshed", id, user, %{}, safe_metadata)
  end

  @doc """
  Creates an audit event for OAuth token refresh failure.
  Records the failure with error details for debugging.
  """
  def oauth_token_refresh_failed_event(credential, error_details) do
    %{id: id, user: user} = Lightning.Repo.preload(credential, :user)

    safe_error_details =
      case error_details do
        %{status: _status} = details ->
          details
          |> Map.take([:status, :error_type, :client_id])
          |> Map.put(:failed_at, DateTime.utc_now())

        error when is_binary(error) ->
          %{error_message: error, failed_at: DateTime.utc_now()}

        _ ->
          %{error_message: "Unknown error", failed_at: DateTime.utc_now()}
      end

    event("token_refresh_failed", id, user, %{}, safe_error_details)
  end

  @doc """
  Creates an audit event for OAuth token revocation.
  Records when tokens are revoked during credential deletion.
  """
  def oauth_token_revoked_event(credential, metadata \\ %{}) do
    %{id: id, user: user} = Lightning.Repo.preload(credential, :user)

    safe_metadata =
      metadata
      |> Map.take([:client_id, :revocation_endpoint, :success])
      |> Map.put(:revoked_at, DateTime.utc_now())

    event("token_revoked", id, user, %{}, safe_metadata)
  end
end
