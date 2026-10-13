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
    changes
  end

  @doc """
  Builds the audit event changeset for a change `actor` made to a credential.

  Environment changes go in metadata rather than in the changes map:

    * `:bodies` - `{name, body}` for each environment written. The bodies are
      stored encrypted and their names listed under `environments`
    * `:deleted` - names of environments removed, listed under
      `deleted_environments`
  """
  @spec user_initiated_event(
          String.t(),
          Lightning.Credentials.Credential.t(),
          Lightning.Actor.t(),
          map() | Ecto.Changeset.t(),
          bodies: [{String.t(), map()}],
          deleted: [String.t()]
        ) :: Ecto.Changeset.t()
  def user_initiated_event(
        event,
        credential,
        actor,
        changes \\ %{},
        environments \\ []
      ) do
    metadata =
      environments
      |> Keyword.get(:bodies, [])
      |> build_metadata_with_bodies()
      |> put_deleted_environments(Keyword.get(environments, :deleted, []))

    event(event, credential.id, actor, changes, metadata)
  end

  defp build_metadata_with_bodies([]), do: %{}

  defp build_metadata_with_bodies(env_bodies) do
    encrypted_bodies =
      Enum.reduce(env_bodies, %{}, fn {env_name, body_data}, acc ->
        encrypted_key = "body:#{env_name}"
        encrypted_value = encrypt_body_for_audit(body_data)
        Map.put(acc, encrypted_key, encrypted_value)
      end)

    %{
      credential_bodies: encrypted_bodies,
      environments: Enum.map(env_bodies, fn {name, _} -> name end)
    }
  end

  defp put_deleted_environments(metadata, []), do: metadata

  defp put_deleted_environments(metadata, deleted),
    do: Map.put(metadata, :deleted_environments, deleted)

  defp encrypt_body_for_audit(body) when is_map(body) do
    {:ok, encrypted} = Lightning.Encrypted.Map.dump(body)
    Base.encode64(encrypted)
  end

  defp encrypt_body_for_audit(_), do: nil

  @doc """
  Creates an audit event for OAuth token refresh success.
  Records the refresh operation with metadata about the OAuth client and scopes.
  """
  def oauth_token_refreshed_event(credential, metadata \\ %{}) do
    %{id: id, user: user} = Lightning.Repo.preload(credential, :user)

    safe_metadata =
      metadata
      |> Map.take([:client_id, :scopes, :expires_in, :token_type, :environment])
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
          |> Map.take([:status, :error_type, :client_id, :environment])
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
      |> Map.take([:client_id, :revocation_endpoint, :success, :environment])
      |> Map.put(:revoked_at, DateTime.utc_now())

    event("token_revoked", id, user, %{}, safe_metadata)
  end
end
