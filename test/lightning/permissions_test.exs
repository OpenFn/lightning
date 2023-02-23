defmodule Lightning.PermissionsTest do
  use Lightning.DataCase, async: true

  import Lightning.ProjectsFixtures
  import Lightning.AccountsFixtures

  alias Lightning.Policies.{Permissions, Users, ProjectUsers}

  setup do
    %{
      superuser: superuser_fixture(),
      user: user_fixture(),
      another_user: user_fixture()
    }
  end

  describe "User policies by instance-wide role" do
    test ":user permissions", %{user: user, another_user: another_user} do
      refute Users |> Permissions.can(:create_projects, user, {})
      refute Users |> Permissions.can(:view_projects, user, {})
      refute Users |> Permissions.can(:edit_projects, user, {})
      refute Users |> Permissions.can(:view_users, user, {})
      refute Users |> Permissions.can(:edit_users, user, {})
      refute Users |> Permissions.can(:delete_users, user, {})
      refute Users |> Permissions.can(:disable_users, user, {})

      refute Users
             |> Permissions.can(:configure_external_auth_provider, user, {})

      refute Users |> Permissions.can(:view_credentials_audit_trail, user, {})

      refute Users |> Permissions.can(:change_password, user, another_user)
      assert Users |> Permissions.can(:change_password, user, user)

      refute Users |> Permissions.can(:delete_account, user, another_user)
      assert Users |> Permissions.can(:delete_account, user, user)

      refute Users |> Permissions.can(:view_credentials, user, another_user)
      assert Users |> Permissions.can(:view_credentials, user, user)

      refute Users |> Permissions.can(:edit_credentials, user, another_user)
      assert Users |> Permissions.can(:edit_credentials, user, user)

      refute Users |> Permissions.can(:delete_credential, user, another_user)
      assert Users |> Permissions.can(:delete_credential, user, user)
    end

    test ":superuser permissions", %{
      superuser: superuser,
      another_user: another_user
    } do
      assert Users |> Permissions.can(:create_projects, superuser, {})
      assert Users |> Permissions.can(:view_projects, superuser, {})
      assert Users |> Permissions.can(:edit_projects, superuser, {})
      assert Users |> Permissions.can(:view_users, superuser, {})
      assert Users |> Permissions.can(:edit_users, superuser, {})
      assert Users |> Permissions.can(:delete_users, superuser, {})
      assert Users |> Permissions.can(:disable_users, superuser, {})

      assert Users
             |> Permissions.can(:configure_external_auth_provider, superuser, {})

      assert Users
             |> Permissions.can(:view_credentials_audit_trail, superuser, {})

      refute Users |> Permissions.can(:change_password, superuser, another_user)
      assert Users |> Permissions.can(:change_password, superuser, superuser)

      refute Users |> Permissions.can(:delete_account, superuser, another_user)
      assert Users |> Permissions.can(:delete_account, superuser, superuser)

      refute Users |> Permissions.can(:view_credentials, superuser, another_user)
      assert Users |> Permissions.can(:view_credentials, superuser, superuser)

      refute Users |> Permissions.can(:edit_credentials, superuser, another_user)
      assert Users |> Permissions.can(:edit_credentials, superuser, superuser)

      refute Users
             |> Permissions.can(:delete_credential, superuser, another_user)

      assert Users |> Permissions.can(:delete_credential, superuser, superuser)
    end
  end

  setup do
    viewer = user_fixture()
    admin = user_fixture()
    owner = user_fixture()
    editor = user_fixture()
    thief = user_fixture()

    project =
      project_fixture(
        project_users: [
          %{user_id: viewer.id, role: :viewer},
          %{user_id: editor.id, role: :editor},
          %{user_id: admin.id, role: :admin},
          %{user_id: owner.id, role: :owner}
        ]
      )

    %{
      project: project,
      viewer: viewer,
      admin: admin,
      owner: owner,
      editor: editor,
      thief: thief
    }
  end

  describe "Project user policies by project user role" do
    test ":viewer permissions", %{project: project, viewer: viewer} do
      refute ProjectUsers |> Permissions.can(:edit_job, viewer, project)
    end

    test "editor permissions", %{project: project, editor: editor} do
      assert ProjectUsers |> Permissions.can(:edit_job, editor, project)
    end

    test "admin permissions", %{project: project, admin: admin} do
      assert ProjectUsers |> Permissions.can(:edit_job, admin, project)
    end

    test "owner permissions", %{project: project, owner: owner} do
      assert ProjectUsers |> Permissions.can(:edit_job, owner, project)
    end

    # For things like :view_job we should be able to show that people who do not
    # have access to a project cannot view the jobs in that project.
    test "thief permissions", %{project: project, thief: thief} do
      refute ProjectUsers |> Permissions.can(:edit_job, thief, project)
    end
  end
end
