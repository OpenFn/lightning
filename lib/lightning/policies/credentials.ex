defmodule Lightning.Policies.Credentials do
  @moduledoc """
  The Bodyguard Policy module for authorizing credential actions.

  Every action needs the `credentials:write` grant.

  A credential belongs to its owner, not to a project. Only the owner or an
  operator may edit a credential, and only the owner may delete one. Only an
  operator may write a credential for someone else (`:name_credential_owner`).
  Listing your credentials needs a caller that can own credentials, which only
  a person can.

  `:create_credential` is asked of the unsaved credential, which names its
  owner. A person may create one for themselves, and an operator for a person.
  So the service account is refused `POST /api/credentials`, which makes the
  caller the owner; it creates through `PUT`, naming one.

  `:see_credential` lets in whoever may edit the credential, and a caller who
  may list the credentials of a project it is linked to. It needs the
  credential's `project_credentials` loaded. Anyone else hears
  `{:error, :no_standing}`, since they may not learn that the credential
  exists.

  Asked with a nil credential, the policy answers for every credential.
  `:see_credential` then says whether the caller may see every credential,
  which only an operator may, and `:delete_credential` whether they may delete
  every credential, which nobody may.

  A caller who may edit a credential scheduled for deletion hears
  `{:error, :scheduled_for_deletion}` for `:edit_credential`. Seeing it and
  deleting it are still allowed, so the deletion can be cancelled or brought
  forward.

  OAuth client actions (`:create_oauth_client`, `:edit_oauth_client`,
  `:delete_oauth_client`) follow ownership as credentials do: a person may
  create one, and only its owner may change or delete it.

  Keychain actions take a project and decide through
  `Lightning.Policies.Decision.project/4`. They need an owner or admin, or a
  support user with no role on a project that allows support access. Creating
  one also needs a person, since it records who created it, so the service
  account may edit and delete keychain credentials but not create them.

  Scheduling a credential's deletion, or cancelling it
  (`:schedule_credential_deletion`), is open to the owner and an operator,
  whether or not it is scheduled. Its environments
  (`:edit_credential_environments`) and linking it to a project
  (`:link_credential`) are open to them too, and refused with
  `{:error, :scheduled_for_deletion}` for a scheduled credential, as editing
  is. Asked with a nil credential, all three say whether the caller may act on
  every credential, which only an operator may.

  Unlinking a credential from a project (`:unlink_credential`) is asked of the
  link, with the credential loaded, on the link's project. It is open to the
  credential's owner, an owner or admin of the project, and an operator.

  Transferring a credential (`:transfer_credential`) is only for its owner, on
  a person's token, so the service account and a repo connection are refused
  before any credential is read. A scheduled credential refuses it with
  `{:error, :scheduled_for_deletion}`, and nobody may transfer every
  credential.
  """
  @behaviour Bodyguard.Policy

  alias Lightning.Accounts.User
  alias Lightning.Credentials.Credential
  alias Lightning.Credentials.KeychainCredential
  alias Lightning.Credentials.OauthClient
  alias Lightning.Policies.Decision
  alias Lightning.Policies.Permissions
  alias Lightning.Policies.ProjectUsers
  alias Lightning.Projects.Project
  alias Lightning.Projects.ProjectCredential
  alias Lightning.Scope
  require Logger

  @type actions ::
          :see_credential
          | :create_credential
          | :edit_credential
          | :delete_credential
          | :name_credential_owner
          | :list_credentials
          | :create_keychain_credential
          | :edit_keychain_credential
          | :delete_keychain_credential
          | :view_keychain_credential
          | :schedule_credential_deletion
          | :edit_credential_environments
          | :link_credential
          | :unlink_credential
          | :transfer_credential
          | :read_credential_schemas
          | :create_oauth_client
          | :edit_oauth_client
          | :delete_oauth_client

  @ownership_actions [
    :create_credential,
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
          | OauthClient.t()
          | ProjectCredential.t()
          | Project.t()
          | nil
          | :before_target
        ) ::
          Decision.answer()
  def authorize(
        :see_credential,
        %Scope{} = scope,
        %Credential{project_credentials: links} = credential
      )
      when is_list(links) do
    case ownership(:edit_credential, scope, credential) do
      false ->
        linked_to_listable_project?(scope, links) || {:error, :no_standing}

      answer ->
        answer
    end
  end

  def authorize(:see_credential, %Scope{} = scope, nil),
    do:
      Decision.instance(scope, nil, "credentials:write", Scope.operator?(scope))

  def authorize(
        :edit_credential,
        %Scope{} = scope,
        %Credential{scheduled_deletion: %DateTime{}} = credential
      ) do
    case ownership(:edit_credential, scope, credential) do
      true -> {:error, :scheduled_for_deletion}
      answer -> answer
    end
  end

  # Unlike `:delete_credential`, open to an operator: nothing is lost until the
  # retention period ends, and the deletion can be cancelled until then.
  def authorize(:schedule_credential_deletion, %Scope{} = scope, subject),
    do: owner_or_operator(scope, subject)

  def authorize(action, %Scope{} = scope, subject)
      when action in [:edit_credential_environments, :link_credential] do
    scope |> owner_or_operator(subject) |> refuse_scheduled(subject)
  end

  def authorize(:unlink_credential, %Scope{} = scope, subject),
    do:
      Decision.project(
        scope,
        subject,
        "credentials:write",
        may_unlink?(scope, subject)
      )

  def authorize(:transfer_credential, %Scope{} = scope, subject) do
    answer =
      scope
      |> Decision.instance(subject, "credentials:write", owner?(scope, subject))
      |> refuse_scheduled(subject)

    Decision.person(scope, answer)
  end

  def authorize(action, %Scope{} = scope, subject)
      when action in @ownership_actions,
      do: ownership(action, scope, subject)

  # A keychain credential records the person who created it, so only a
  # person may create one.
  def authorize(:create_keychain_credential, %Scope{} = scope, subject),
    do:
      Decision.project(
        scope,
        subject,
        "credentials:write",
        admin_or_support?(scope) and Scope.person?(scope)
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

  # An OAuth client belongs to the person who created it, as a credential
  # does, and only they may change or delete it. Only a person can own one.
  # Asked with a nil client, editing and deleting answer for every client,
  # which nobody may touch.
  def authorize(:create_oauth_client, %Scope{} = scope, subject),
    do:
      Decision.instance(
        scope,
        subject,
        "credentials:write",
        scope.can_own_credentials?
      )

  def authorize(action, %Scope{} = scope, subject)
      when action in [:edit_oauth_client, :delete_oauth_client],
      do:
        Decision.instance(
          scope,
          subject,
          "credentials:write",
          owns_oauth_client?(scope, subject)
        )

  # The credential types are the same for everyone holding the grant.
  def authorize(:read_credential_schemas, %Scope{} = scope, _subject),
    do: Decision.instance(scope, nil, "credentials:write", true)

  def authorize(action, actor, subject)
      when action in @ownership_actions and
             (is_struct(subject, Credential) or is_nil(subject)) do
    authorize(action, Scope.new(actor), subject)
  end

  def authorize(action, actor, subject)
      when action in [
             :schedule_credential_deletion,
             :edit_credential_environments,
             :link_credential
           ] and (is_struct(subject, Credential) or is_nil(subject)) do
    authorize(action, Scope.new(actor), subject)
  end

  def authorize(:unlink_credential, actor, %ProjectCredential{} = link),
    do:
      Permissions.for_actor(
        actor,
        link,
        &authorize(:unlink_credential, &1, link)
      )

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

  defp ownership(action, scope, subject),
    do:
      Decision.instance(
        scope,
        subject,
        "credentials:write",
        owns?(action, scope, subject)
      )

  defp owns?(
         :create_credential,
         %Scope{actor: %{id: id}} = scope,
         %Credential{user_id: id}
       ),
       do: scope.can_own_credentials?

  defp owns?(:create_credential, scope, %Credential{}),
    do: Scope.operator?(scope)

  defp owns?(:edit_credential, scope, %Credential{user_id: owner_id}),
    do: scope.actor.id == owner_id or Scope.operator?(scope)

  # An operator may write a credential but never delete one at once. It may
  # schedule a deletion (`:schedule_credential_deletion`), which waits out the
  # retention period and can be cancelled until then.
  defp owns?(:delete_credential, scope, %Credential{user_id: owner_id}),
    do: scope.actor.id == owner_id

  defp owns?(:name_credential_owner, scope, nil), do: Scope.operator?(scope)

  defp owns?(:list_credentials, scope, nil), do: scope.can_own_credentials?

  defp owns?(_action, _scope, _subject), do: false

  defp owner_or_operator(scope, subject),
    do:
      Decision.instance(
        scope,
        subject,
        "credentials:write",
        owner?(scope, subject) or Scope.operator?(scope)
      )

  defp owner?(scope, %Credential{user_id: owner_id}),
    do: scope.actor.id == owner_id

  defp owner?(_scope, _subject), do: false

  defp refuse_scheduled(true, %Credential{scheduled_deletion: %DateTime{}}),
    do: {:error, :scheduled_for_deletion}

  defp refuse_scheduled(answer, _subject), do: answer

  defp may_unlink?(scope, %ProjectCredential{
         credential: %Credential{} = credential
       }),
       do:
         Scope.holds_role?(scope, [:owner, :admin]) or owner?(scope, credential)

  defp may_unlink?(_scope, _subject), do: false

  defp owns_oauth_client?(%Scope{actor: %User{id: id}}, %OauthClient{user_id: id}),
       do: true

  defp owns_oauth_client?(_scope, _subject), do: false

  defp linked_to_listable_project?(scope, links) do
    scope
    |> Scope.fetch_all(Enum.map(links, & &1.project_id))
    |> Enum.any?(fn {_id, project_scope} ->
      ProjectUsers.permitted?(:list_project_credentials, project_scope)
    end)
  end

  # Deliberately looser than ProjectUsers, where a support user with no
  # membership row gets nothing at admin level. Keychain access on a consenting
  # project is the pre-existing rule from allow_as_support_user?/2, kept rather
  # than tightened — narrowing it is a support-workflow decision, not a fix.
  defp admin_or_support?(scope),
    do:
      Scope.holds_role?(scope, [:owner, :admin]) or
        (is_nil(scope.role) and scope.support?)
end
