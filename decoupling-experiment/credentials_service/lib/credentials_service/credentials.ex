defmodule CredentialsService.Credentials do
  @moduledoc """
  The Credentials context: the slice's public API.

  This is a faithful but trimmed extraction of `Lightning.Credentials`. It keeps
  the parts that exercise the real coupling and stubs/omits the rest (OAuth
  refresh HTTP, transfer email flow, the `purge_deleted` Oban cron) with notes
  pointing at `docs/migration-analysis.md`.

  Invariant: **credential body values never leave this module.** Callers receive
  structs whose `credential_bodies` are loaded for metadata (environment names)
  but the JSON layer never serializes `body`.
  """
  import Ecto.Query, warn: false

  alias CredentialsService.Repo
  alias CredentialsService.Credentials.Credential
  alias CredentialsService.Projects.ProjectCredential
  alias Ecto.Multi

  @preloads [:credential_bodies, :project_credentials]

  @doc "List a user's own credentials."
  def list_credentials(user_id) when is_binary(user_id) do
    Credential
    |> where([c], c.user_id == ^user_id)
    |> preload(^@preloads)
    |> Repo.all()
  end

  @doc "List every credential shared with a project (via the join)."
  def list_credentials_for_project(project_id) when is_binary(project_id) do
    from(c in Credential,
      join: pc in ProjectCredential,
      on: pc.credential_id == c.id,
      where: pc.project_id == ^project_id,
      preload: ^@preloads
    )
    |> Repo.all()
  end

  @doc "Fetch one credential, or nil (also nil for a non-UUID id)."
  def get_credential(id) do
    case Ecto.UUID.cast(id) do
      {:ok, uuid} -> Credential |> Repo.get(uuid) |> preload_loaded()
      :error -> nil
    end
  end

  defp preload_loaded(nil), do: nil
  defp preload_loaded(%Credential{} = c), do: Repo.preload(c, @preloads)

  @doc """
  Create a credential and its environment bodies.

  Accepts either the multi-environment `"bodies" => %{"main" => %{...}}` form or
  the older single `"body" => %{...}` form (stored as the "main" environment).

  In Lightning this is an `Ecto.Multi` that also derives audit events; here it is
  a single insert with `cast_assoc`. The audit-trail derivation is called out as
  a "difficult to move" item rather than reimplemented.
  """
  def create_credential(attrs) do
    attrs = normalize_bodies(attrs)

    %Credential{}
    |> Credential.changeset(attrs)
    |> Repo.insert()
    |> case do
      {:ok, credential} -> {:ok, Repo.preload(credential, @preloads)}
      {:error, _changeset} = error -> error
    end
  end

  defp normalize_bodies(%{"bodies" => bodies} = attrs) when is_map(bodies) do
    cast = for {name, body} <- bodies, do: %{"name" => name, "body" => body}

    attrs
    |> Map.drop(["bodies", "body"])
    |> Map.put("credential_bodies", cast)
  end

  defp normalize_bodies(%{"body" => body} = attrs) when is_map(body) do
    attrs
    |> Map.drop(["body"])
    |> Map.put("credential_bodies", [%{"name" => "main", "body" => body}])
  end

  defp normalize_bodies(attrs), do: attrs

  @doc """
  Delete a credential.

  This is the clearest "Ecto.Multi across context boundaries" finding. In the
  monolith, `schedule_credential_deletion` does, in ONE transaction:
    1. delete `project_credentials` rows          (owned here)
    2. `update_all` to null `jobs.project_credential_id`  (owned by Workflows)
    3. revoke OAuth tokens over HTTP              (AuthProviders)
    4. email the owner                            (Accounts)

  Across a service boundary, only step 1 stays a local DB transaction. Steps
  2-4 become cross-service calls/events that cannot participate in this
  transaction. `remove_external_associations/1` marks exactly that seam.
  """
  def delete_credential(%Credential{} = credential) do
    Multi.new()
    |> Multi.delete_all(
      :project_credentials,
      from(pc in ProjectCredential, where: pc.credential_id == ^credential.id)
    )
    |> Multi.delete(:credential, credential)
    |> Repo.transaction()
    |> case do
      {:ok, _changes} ->
        :ok = remove_external_associations(credential)
        {:ok, credential}

      {:error, _op, value, _changes} ->
        {:error, value}
    end
  end

  # STUB SEAM: in Lightning this nulls jobs.project_credential_id and
  # keychain_credentials.default_credential_id (tables owned by Workflows) and
  # revokes OAuth tokens. Here it is a no-op standing in for a cross-service
  # call/event. NOT silently faked: this is documented in migration-analysis.md.
  defp remove_external_associations(_credential), do: :ok

  # --- Pure logic lifted from Lightning.Credentials (no DB) -----------------

  @oauth_expiry_buffer_seconds 300

  @doc """
  Whether an OAuth token body is expired, with Lightning's 5-minute buffer.
  Pure: takes the body map and a reference time (defaults to now).
  """
  def oauth_token_expired?(body, now_unix \\ System.os_time(:second))

  def oauth_token_expired?(%{"expires_at" => expires_at}, now_unix)
      when is_integer(expires_at) do
    expires_at - @oauth_expiry_buffer_seconds <= now_unix
  end

  def oauth_token_expired?(_body, _now), do: false

  @doc "Collect candidate sensitive (string) values from a body for scrubbing."
  defdelegate sensitive_values(body),
    to: CredentialsService.Credentials.CredentialBody
end
