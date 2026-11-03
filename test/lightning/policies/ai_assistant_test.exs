defmodule Lightning.Policies.AiAssistantTest do
  @moduledoc """
  Only a person's session token may use the AI assistant. On it, any member of
  the project may read its sessions and chat, viewers included, with the
  project's standing, MFA and deletion checks.
  """
  use Lightning.DataCase, async: true

  alias Lightning.Policies.AiAssistant
  alias Lightning.Scope
  alias Lightning.ServiceAccount.AccessToken

  @actions [:read_ai_sessions, :chat]

  defp session_scope(user, project),
    do: Scope.fetch(Scope.new(user, token_kind: :session), project)

  test "a session token of any member may read and chat, viewers included" do
    for role <- [:viewer, :editor, :admin, :owner] do
      user = insert(:user)
      project = insert(:project, project_users: [%{user: user, role: role}])
      {:ok, scope} = session_scope(user, project)

      for action <- @actions,
          do: assert(AiAssistant.authorize(action, scope, project) == true)
    end
  end

  test "any other token is refused before the project is consulted, and step-up isn't needed" do
    user = insert(:user)
    project = insert(:project, project_users: [%{user: user, role: :owner}])
    {account, _key} = Lightning.ServiceAccountHelpers.service_account_with_key()

    {:ok, personal} =
      Scope.fetch(Scope.new(user, token_kind: :personal_access_token), project)

    {:ok, operator} =
      Scope.fetch(
        Scope.new(%{account | grants: MapSet.new(AccessToken.scopes())},
          token_kind: :access_token
        ),
        project
      )

    for scope <- [personal, operator], action <- @actions do
      assert AiAssistant.authorize(action, scope, project) == false

      assert AiAssistant.authorize(
               action,
               Scope.new(scope.actor),
               :before_target
             ) == false
    end

    session = Scope.new(user, token_kind: :session)

    for action <- @actions,
        do:
          assert(AiAssistant.authorize(action, session, :before_target) == true)
  end

  test "a non-member has no standing, and a member without the MFA the project requires, or on a project scheduled for deletion, is refused" do
    stranger = insert(:user)
    unenrolled = insert(:user, mfa_enabled: false)
    member = insert(:user)

    mfa_project =
      insert(:project,
        requires_mfa: true,
        project_users: [%{user: unenrolled, role: :owner}]
      )

    scheduled =
      insert(:project,
        scheduled_deletion: DateTime.utc_now(),
        project_users: [%{user: member, role: :owner}]
      )

    {:ok, no_standing} = session_scope(stranger, mfa_project)
    {:ok, no_mfa} = session_scope(unenrolled, mfa_project)
    {:ok, deleting} = session_scope(member, scheduled)

    for action <- @actions do
      assert AiAssistant.authorize(action, no_standing, mfa_project) ==
               {:error, :no_standing}

      assert AiAssistant.authorize(action, no_mfa, mfa_project) == false

      assert AiAssistant.authorize(action, deleting, scheduled) ==
               {:error, :scheduled_for_deletion}
    end
  end
end
