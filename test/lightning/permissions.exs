defmodule Lightning.PermissionsTest do
  use Lightning.DataCase, async: true

  import Lightning.ProjectsFixtures
  import Lightning.AccountsFixtures

  alias Lightning.Policies.{Permissions, Users, ProjectUsers}

  setup do
    superuser = superuser_fixture()
    user = user_fixture()
  end

  describe "User policies by instance-wide role" do
    test ":user permissions", %{user: user} do
      refute Users |> Permissions.can(:create_projects, user, {})
    end

    test ":superuser permissions", %{superuser: superuser} do
      assert Users |> Permissions.can(:create_projects, superuser, {})
    end
  end

  setup do
    viewer = user_fixture()
    admin = user_fixture()
    owner = user_fixture()
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

    %{project: project, viewer: viewer, admin: admin, owner: owner, thief: thief}
  end

  describe "Project user policies by project user role" do
    test ":viewer permissions", %{project: project, viewer: viewer} do
      refute ProjectUsers |> Permissions.can(:edit_jobs, viewer, project)
    end

    test "editor permissions", %{project: project, editor: editor} do
      assert ProjectUsers |> Permissions.can(:edit_jobs, editor, project)
    end

    test "admin permissions", %{project: project, viewer: admin} do
      assert ProjectUsers |> Permissions.can(:edit_jobs, admin, project)
    end

    test "owner permissions", %{project: project, owner: owner} do
      assert ProjectUsers |> Permissions.can(:edit_jobs, owner, project)
    end
  end
end
