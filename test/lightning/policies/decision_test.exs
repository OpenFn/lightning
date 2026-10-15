defmodule Lightning.Policies.DecisionTest do
  @moduledoc """
  Only a caller the policy would otherwise allow learns that a project is
  scheduled for deletion, in every policy that decides through
  `Lightning.Policies.Decision`.
  """
  use Lightning.DataCase, async: true

  alias Lightning.Policies.Collections
  alias Lightning.Policies.Credentials
  alias Lightning.Policies.ProjectUsers
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

  test "a stranger is refused, never told about the deletion", %{
    project: project,
    stranger: stranger
  } do
    for {policy, actions} <- @project_actions, action <- actions do
      assert policy.authorize(action, stranger, project) == false,
             "#{inspect(policy)} #{action}"
    end
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
