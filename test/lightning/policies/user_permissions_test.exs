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
      other_user: another_user
    } do
      assert Users |> Permissions.can(:delete_account, user, user.id)
      refute Users |> Permissions.can(:delete_account, user, another_user.id)
    end

    test "can only delete their own api tokens", %{
      user: user,
      other_user: another_user
    } do
      #1.  Create a api token for user
      #2. Assert that you can delete it
      #3 Create a api token for another_user
      #4 Assert that another user can delete it
      #5 Now refute that user can delete another user's token and vice versa
      assert Users |> Permissions.can(:delete_account, user, user.id)
      refute Users |> Permissions.can(:delete_account, user, another_user.id)
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
    test "can manage any users account", %{
      superuser: superuser,
      other_user: other_user
    } do
      assert Users |> Permissions.can(:create_projects, superuser, {})
      assert Users |> Permissions.can(:view_projects, superuser, {})
      assert Users |> Permissions.can(:edit_projects, superuser, {})
      assert Users |> Permissions.can(:create_users, superuser, {})
      assert Users |> Permissions.can(:view_users, superuser, {})
      assert Users |> Permissions.can(:edit_users, superuser, {})
      assert Users |> Permissions.can(:delete_users, superuser, {})
      assert Users |> Permissions.can(:disable_users, superuser, {})
      assert Users |> Permissions.can(:access_admin_space, superuser, {})

      assert Users
             |> Permissions.can(:configure_external_auth_provider, superuser, {})

      assert Users
             |> Permissions.can(:view_credentials_audit_trail, superuser, {})

      refute Users |> Permissions.can(:delete_account, superuser, other_user.id)
      assert Users |> Permissions.can(:delete_account, superuser, superuser.id)
    end
  end
end
