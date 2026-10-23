defmodule Lightning.Policies.DecisionTest do
  @moduledoc """
  Only a caller the policy would otherwise allow learns that a project is
  scheduled for deletion, and a caller with no standing hears that apart from
  a missing role or MFA, in every policy that decides through
  `Lightning.Policies.Decision`.
  """
  use Lightning.DataCase, async: true

  alias Lightning.Policies.Collections
  alias Lightning.Policies.Credentials
  alias Lightning.Policies.ProjectUsers
  alias Lightning.Policies.Provisioning
  alias Lightning.Policies.Users
  alias Lightning.Scope
  alias Lightning.ServiceAccount.AccessToken

  @project_actions [
    {ProjectUsers, ProjectUsers.actions()},
    {Collections,
     [
       :access_collection,
       :put_collection_item,
       :delete_collection_item,
       :delete_all_collection_items,
       :manage_collection
     ]},
    {Credentials,
     [
       :create_keychain_credential,
       :edit_keychain_credential,
       :delete_keychain_credential,
       :view_keychain_credential
     ]}
  ]

  @instance_actions [
    {Credentials,
     [
       :edit_credential,
       :delete_credential,
       :name_credential_owner,
       :list_credentials
     ]},
    {Users, [:read_users, :write_users]}
  ]

  setup do
    project =
      insert(:project,
        scheduled_deletion: DateTime.add(DateTime.utc_now(), 7, :day)
      )

    {account, _key} = Lightning.ServiceAccountHelpers.service_account_with_key()

    {:ok, operator} =
      Scope.fetch(%{account | grants: MapSet.new(AccessToken.scopes())}, project)

    {:ok, grantless} = Scope.fetch(%{account | grants: MapSet.new()}, project)
    {:ok, stranger} = Scope.fetch(insert(:user), project)

    %{
      project: project,
      operator: operator,
      grantless: grantless,
      stranger: stranger
    }
  end

  test "an allowed caller is told the project is scheduled for deletion", %{
    project: project,
    operator: operator
  } do
    for {policy, action} <- [
          {ProjectUsers, :access_project},
          {Collections, :manage_collection},
          {Credentials, :view_keychain_credential}
        ] do
      assert policy.authorize(action, operator, project) ==
               {:error, :scheduled_for_deletion}
    end
  end

  test "a caller without the grant hears which grant, never the deletion",
       %{project: project, grantless: grantless} do
    for {policy, actions} <- @project_actions, action <- actions do
      assert policy.authorize(action, grantless, project) ==
               {:error, {:insufficient_scope, grant(policy, action)}},
             "#{inspect(policy)} #{action}"
    end

    instance = Scope.new(grantless.actor)

    for {policy, actions} <- @instance_actions, action <- actions do
      assert policy.authorize(action, instance, nil) ==
               {:error, {:insufficient_scope, grant(policy, action)}},
             "#{inspect(policy)} #{action}"
    end
  end

  test "a stranger is told only that it has no standing, never about the deletion",
       %{project: project, stranger: stranger} do
    for {policy, actions} <- @project_actions, action <- actions do
      assert policy.authorize(action, stranger, project) ==
               {:error, :no_standing},
             "#{inspect(policy)} #{action}"
    end
  end

  describe "on a project that requires MFA" do
    setup do
      %{project: insert(:project, requires_mfa: true)}
    end

    test "a non-member has no standing, even without MFA", %{project: project} do
      {:ok, scope} = Scope.fetch(insert(:user, mfa_enabled: false), project)

      assert ProjectUsers.authorize(:access_project, scope, project) ==
               {:error, :no_standing}
    end

    test "a member without MFA is refused", %{project: project} do
      member = insert(:user, mfa_enabled: false)
      insert(:project_user, project: project, user: member, role: :owner)
      {:ok, scope} = Scope.fetch(member, project)

      assert ProjectUsers.authorize(:access_project, scope, project) == false
    end

    test "an enrolled member without the role is refused", %{project: project} do
      member = insert(:user, mfa_enabled: true)
      insert(:project_user, project: project, user: member, role: :viewer)
      {:ok, scope} = Scope.fetch(member, project)

      assert ProjectUsers.authorize(:access_project, scope, project) == true
      assert ProjectUsers.authorize(:edit_project, scope, project) == false
    end
  end

  test "a person asking without a scope is refused with false, standing or not" do
    project = insert(:project)

    assert ProjectUsers.authorize(:access_project, insert(:user), project) ==
             false
  end

  test "a repo connection is allowed on its own project and refused another" do
    project = insert(:project)
    repo_connection = insert(:project_repo_connection, project: project)
    {:ok, scope} = Scope.fetch(repo_connection, project)

    assert Provisioning.authorize(:provision_project, scope, project) == true
    assert Provisioning.authorize(:describe_project, scope, project) == true

    assert Scope.fetch(repo_connection, insert(:project)) ==
             {:error, :no_standing}
  end

  defp grant(ProjectUsers, action)
       when action in [:create_project_credential, :list_project_credentials],
       do: "credentials:write"

  defp grant(ProjectUsers, _action), do: "projects:write"
  defp grant(Collections, _action), do: "collections:write"
  defp grant(Credentials, _action), do: "credentials:write"
  defp grant(Users, :read_users), do: "users:read"
  defp grant(Users, :write_users), do: "users:write"
end
