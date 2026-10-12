defmodule Lightning.Policies.Credentials do
  @moduledoc """
  The Bodyguard Policy module for authorizing credential actions.

  Every action needs the `credentials:write` grant.

  A credential belongs to its owner, not to a project, so these actions never
  look at a project. Only the owner or an operator may edit a credential, and
  only the owner may delete one. Only an operator may write a credential for
  someone else (`:name_credential_owner`). Listing your credentials, or creating
  one for yourself, needs a caller that can own credentials, which only a
  person can.

  `Lightning.Credentials`, not this policy, refuses a credential scheduled for
  deletion.

  Keychain actions take a project and decide through
  `Lightning.Policies.Decision.project/4`. They need an owner or admin, or a
  support user with no role on a project that allows support access.
  """
  @behaviour Bodyguard.Policy

  alias Lightning.Credentials.Credential
  alias Lightning.Credentials.KeychainCredential
  alias Lightning.Policies.Decision
  alias Lightning.Policies.Permissions
  alias Lightning.Projects.Project
  alias Lightning.Scope
  require Logger

  @type actions ::
          :edit_credential
          | :delete_credential
          | :name_credential_owner
          | :list_credentials
          | :create_keychain_credential
          | :edit_keychain_credential
          | :delete_keychain_credential
          | :view_keychain_credential

  @ownership_actions [
    :edit_credential,
    :delete_credential,
    :name_credential_owner,
    :list_credentials
  ]

  @keychain_actions [
    :create_keychain_credential,
    :edit_keychain_credential,
    :delete_keychain_credential,
    :view_keychain_credential
  ]

  @spec authorize(
          actions(),
          Scope.t() | Scope.actor(),
          Credential.t()
          | KeychainCredential.t()
          | Project.t()
          | nil
          | :before_target
        ) ::
          boolean() | {:error, :insufficient_scope | :scheduled_for_deletion}
  def authorize(action, %Scope{} = scope, subject)
      when action in @ownership_actions,
      do:
        Decision.instance(
          scope,
          subject,
          "credentials:write",
          owns?(action, scope, subject)
        )

  def authorize(action, %Scope{} = scope, subject)
      when action in @keychain_actions,
      do:
        Decision.project(
          scope,
          subject,
          "credentials:write",
          admin_or_support?(scope)
        )

  def authorize(action, actor, subject)
      when action in @ownership_actions and
             (is_struct(subject, Credential) or is_nil(subject)) do
    authorize(action, Scope.new(actor), subject)
  end

  # :create_keychain_credential can be asked with a project or a keychain
  # credential. The context function holds an unsaved keychain rather than a
  # project, so without the keychain clause it would refuse every creation.
  def authorize(action, actor, subject)
      when action in @keychain_actions and
             (is_struct(subject, Project) or
                is_struct(subject, KeychainCredential)) do
    Permissions.for_actor(actor, subject, &authorize(action, &1, subject))
  end

  # Deny by default: a call site passing the wrong shape fails closed rather
  # than raising. Reaching this clause is a bug in the caller — but the debug
  # line is filtered out at prod's :info level, so seeing none of these is not
  # evidence that nobody is hitting it.
  def authorize(action, actor, resource) do
    Logger.debug(fn ->
      "Refused #{inspect(action)} for #{inspect(actor, limit: 2)} " <>
        "on #{inspect(resource, limit: 3)}: no matching policy clause"
    end)

    false
  end

  # Creating a credential for yourself makes you its owner, which only a caller
  # that can own credentials may be.
  defp owns?(
         :edit_credential,
         %Scope{actor: %{id: id}} = scope,
         %Credential{id: nil, user_id: id}
       ),
       do: scope.can_own_credentials?

  defp owns?(:edit_credential, scope, %Credential{user_id: owner_id}),
    do: scope.actor.id == owner_id or Scope.operator?(scope)

  # An operator may write a credential but never delete one.
  defp owns?(:delete_credential, scope, %Credential{user_id: owner_id}),
    do: scope.actor.id == owner_id

  defp owns?(:name_credential_owner, scope, nil), do: Scope.operator?(scope)

  defp owns?(:list_credentials, scope, nil), do: scope.can_own_credentials?

  defp owns?(_action, _scope, _subject), do: false

  # Deliberately looser than ProjectUsers, where a support user with no
  # membership row gets nothing at admin level. Keychain access on a consenting
  # project is the pre-existing rule from allow_as_support_user?/2, kept rather
  # than tightened — narrowing it is a support-workflow decision, not a fix.
  defp admin_or_support?(scope),
    do:
      Scope.holds_role?(scope, [:owner, :admin]) or
        (is_nil(scope.role) and scope.support?)
end
