defmodule Lightning.Policies.UserPermissionsTest do
  @moduledoc """
  User permissions determine what a user can and cannot do across a Lightning
  instance. Note that users have a `role` which is either `superuser` or
  `user`. A superuser is assumed to have full infrastructure and database
  access across the instance/deployment of Lightning, and a user does not.

  Typically, there is only one superuser per deployment of Lightning.

  Regular users have full control over their own OAuth clients, but cannot
  modify other users' clients. Credentials are decided by
  `Lightning.Policies.Credentials`. All other resources in Lightning are under
  the control of Project User Permissions and are demonstrated in the
  ProjectUserPermissionsTest.
  """
  use Lightning.DataCase, async: true

  import Lightning.AccountsFixtures

  alias Lightning.Policies.Permissions
  alias Lightning.Policies.Users

  setup do
    %{
      superuser: superuser_fixture(),
      user: user_fixture(),
      other_user: user_fixture()
    }
  end

  describe "Users" do
    test "can edit and delete their own OAuth clients and delete their own accounts and api tokens",
         %{
           user: user
         } do
      api_token =
        build(:user_token, user: user)
        |> with_personal_access_token()
        |> insert()

      client = insert(:oauth_client, user: user)

      assert Users |> Permissions.can?(:edit_credential, user, client)
      assert Users |> Permissions.can?(:delete_account, user, user)
      assert Users |> Permissions.can?(:delete_api_token, user, api_token.token)
      assert Users |> Permissions.can?(:delete_credential, user, client)
    end

    test "cannot access admin space, edit or delete other users' OAuth clients, or delete other users' accounts and api tokens",
         %{
           user: user,
           other_user: other_user
         } do
      api_token =
        build(:user_token, user: other_user)
        |> with_personal_access_token()
        |> insert()

      client = insert(:oauth_client, user: other_user)

      refute Users |> Permissions.can?(:access_admin_space, user)
      refute Users |> Permissions.can?(:edit_credential, user, client)
      refute Users |> Permissions.can?(:delete_account, user, other_user)
      refute Users |> Permissions.can?(:delete_api_token, user, api_token.token)
      refute Users |> Permissions.can?(:delete_credential, user, client)
    end
  end

  describe "Superusers" do
    test "can access admin space and delete their own accounts and api tokens",
         %{
           superuser: superuser
         } do
      api_token =
        build(:user_token, user: superuser)
        |> with_personal_access_token()
        |> insert()

      assert Users |> Permissions.can?(:access_admin_space, superuser)
      assert Users |> Permissions.can?(:delete_account, superuser, superuser)

      assert Users
             |> Permissions.can?(:delete_api_token, superuser, api_token.token)
    end

    test "cannot edit or delete other users' OAuth clients, or delete other users' accounts and api tokens",
         %{
           superuser: superuser,
           other_user: other_user
         } do
      api_token =
        build(:user_token, user: other_user)
        |> with_personal_access_token()
        |> insert()

      client = insert(:oauth_client, user: other_user)

      refute Users |> Permissions.can?(:edit_credential, superuser, client)
      refute Users |> Permissions.can?(:delete_account, superuser, other_user)

      refute Users
             |> Permissions.can?(:delete_api_token, superuser, api_token.token)

      refute Users |> Permissions.can?(:delete_credential, superuser, client)
    end
  end
end
