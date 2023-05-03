defmodule Lightning.UserPermissionsTest do
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
    test "can only delete their own accounts", %{
      user: user,
      other_user: other_user
    } do
      assert Users |> Permissions.can(:delete_account, user, user)
      refute Users |> Permissions.can(:delete_account, user, other_user)
    end

    test "can only delete their own api tokens", %{
      user: user,
      other_user: other_user
    } do
      user_api_token = api_token_fixture(user).token
      other_user_api_token = api_token_fixture(other_user).token

      assert Users
             |> Permissions.can(
               :delete_api_token,
               user,
               user_api_token
             )

      refute Users
             |> Permissions.can(
               :delete_api_token,
               user,
               other_user_api_token
             )
    end

    test "can only edit & delete their own credentials", %{user: user} do
      user_cred = CredentialsFixtures.credential_fixture(user_id: user.id)
      other_cred = CredentialsFixtures.credential_fixture()

      assert Users |> Permissions.can(:edit_credential, user, user_cred)
      assert Users |> Permissions.can(:delete_credential, user, user_cred)

      refute Users |> Permissions.can(:edit_credential, user, other_cred)
      refute Users |> Permissions.can(:delete_credential, user, other_cred)
    end

    test "can't access admin settings", %{
      user: user
    } do
      refute Users |> Permissions.can(:access_admin_space, user, {})
    end
  end

  describe "Superusers" do
    test "can access admin settings", %{
      superuser: superuser
    } do
      assert Users |> Permissions.can(:access_admin_space, superuser, {})
    end
  end
end
