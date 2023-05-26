defmodule Lightning.Policies.UserPermissionsTest do
  @moduledoc """
  User permissions determine what a user can and cannot do across a Lightning
  instance. Note that users have a `role` which is either `superuser` or
  `user`. A superuser is assumed to have full infrastructure and database
  access across the instance/deployment of Lightning, and a user does not.

  Typically, there is only one superuser per deployment of Lightning.

  Regular users have full control over their own credentials, but cannot see or
  modify other user's credentials. All other resources in Lightning are under
  the control of Project User Permissions and are demonstrated in the
  ProjectUserPermissionsTest.
  """
  use Lightning.DataCase, async: true

  import Lightning.AccountsFixtures

  alias Lightning.CredentialsFixtures
  alias Lightning.Policies.{Permissions, Users}

  setup do
    %{
      superuser: superuser_fixture(),
      user: user_fixture(),
      other_user: user_fixture()
    }
  end

  describe "Users" do
    test "can edit their own credentials and delete their own accounts, api tokens, and credentials.",
         %{
           user: user
         } do
      user_api_token = api_token_fixture(user).token
      user_cred = CredentialsFixtures.credential_fixture(user_id: user.id)

      assert Users |> Permissions.can?(:edit_credential, user, user_cred)
      assert Users |> Permissions.can?(:delete_account, user, user)

      assert Users
             |> Permissions.can?(
               :delete_api_token,
               user,
               user_api_token
             )

      assert Users |> Permissions.can?(:delete_credential, user, user_cred)
    end

    test "cannot access admin space, edit other users credentials, and delete other users accounts, api tokens, and credentials",
         %{
           user: user,
           other_user: other_user
         } do
      other_user_api_token = api_token_fixture(other_user).token
      other_user_credential = CredentialsFixtures.credential_fixture()

      refute Users |> Permissions.can?(:access_admin_space, user, {})

      refute Users
             |> Permissions.can?(:edit_credential, user, other_user_credential)

      refute Users |> Permissions.can?(:delete_account, user, other_user)

      refute Users
             |> Permissions.can?(
               :delete_api_token,
               user,
               other_user_api_token
             )

      refute Users
             |> Permissions.can?(:delete_credential, user, other_user_credential)
    end
  end

  describe "Superusers" do
    test "can access admin space, edit their own credentials, and delete their own accounts, api tokens, and credentials.",
         %{
           superuser: superuser
         } do
      api_token = api_token_fixture(superuser).token
      credential = CredentialsFixtures.credential_fixture(user_id: superuser.id)

      assert Users |> Permissions.can?(:access_admin_space, superuser, {})

      assert Users |> Permissions.can?(:edit_credential, superuser, credential)
      assert Users |> Permissions.can?(:delete_account, superuser, superuser)

      assert Users
             |> Permissions.can?(
               :delete_api_token,
               superuser,
               api_token
             )

      assert Users |> Permissions.can?(:delete_credential, superuser, credential)
    end

    test "cannot edit other users credentials, and delete other users accounts, api tokens, and credentials",
         %{
           superuser: superuser,
           other_user: other_user
         } do
      other_user_api_token = api_token_fixture(other_user).token
      other_user_credential = CredentialsFixtures.credential_fixture()

      refute Users
             |> Permissions.can?(
               :edit_credential,
               superuser,
               other_user_credential
             )

      refute Users |> Permissions.can?(:delete_account, superuser, other_user)

      refute Users
             |> Permissions.can?(
               :delete_api_token,
               superuser,
               other_user_api_token
             )

      refute Users
             |> Permissions.can?(
               :delete_credential,
               superuser,
               other_user_credential
             )
    end
  end
end
