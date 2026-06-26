defmodule CredentialsService.Stubs do
  @moduledoc """
  Documented stubs for the surfaces NOT migrated in this slice.

  Phase 3 deliberately migrates ONLY Credentials. The other surfaces are
  represented here as clearly-marked stubs so the boundary is explicit and so
  nothing is silently faked. Each function raises if called. See
  `docs/page-inventory.md` (full map) and `docs/migration-analysis.md`
  (per-surface "Difficult to move").
  """

  defmodule Accounts do
    @moduledoc """
    STUB. Owns `users`/identity. Credentials depends on it via
    `credentials.user_id` and the transfer flow (mint UserToken + email). Across
    the boundary this becomes a user-identity + token-verification contract.
    """
    def get_user(_id), do: raise("STUB: Accounts is not part of the Credentials slice")
  end

  defmodule Projects do
    @moduledoc """
    STUB. Owns `projects` and `project_users` (roles). Credential project-scoping
    and the Bodyguard `:access_project` / `:create_project_credential` checks
    depend on project membership. The slice treats `project_id` as opaque.
    """
    def get_project(_id), do: raise("STUB: Projects is not part of the Credentials slice")

    def member_can?(_action, _user_id, _project_id),
      do: raise("STUB: project-membership authorization lives in the Projects service")
  end

  defmodule Workflows do
    @moduledoc """
    STUB. Owns `jobs` (and `jobs.project_credential_id` / `keychain_credential_id`).
    Credential deletion must null these FKs; across the boundary that is a
    cross-service call, not the in-DB `update_all` it is today.
    """
    def null_credential_references(_credential_id),
      do: raise("STUB: jobs.project_credential_id is owned by the Workflows service")
  end

  defmodule AuthProviders do
    @moduledoc """
    STUB. Owns the OAuth HTTP client (token refresh/revoke). The hot-path
    refresh during a run, and revoke-on-delete, call out to this. Genuinely
    stateful + network-bound; see migration-analysis.md.
    """
    def refresh_token(_client, _body),
      do: raise("STUB: OAuth refresh HTTP lives in the AuthProviders service")
  end

  defmodule Auditing do
    @moduledoc """
    STUB. Append-only audit trail. Lightning emits 9 credential audit events,
    some INSIDE the deletion/transfer Ecto.Multi. Across the boundary the
    service either keeps writing audit rows or publishes events the monolith
    persists.
    """
    def audit(_event, _credential), do: raise("STUB: Auditing is a cross-cutting concern")
  end
end
