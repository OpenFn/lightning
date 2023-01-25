defmodule Lightning.PermissionsTest do
  use Lightning.DataCase, async: true

  import Lightning.ProjectsFixtures
  import Lightning.AccountsFixtures

  describe "Users policies" do
    test "normal users can't create projects" do
      user = user_fixture()

      refute Lightning.Policies.Permissions.can(
               Lightning.Policies.UserPolicy,
               :create_projects,
               user,
               {}
             )
    end

    test "superusers can create projects" do
      superuser = superuser_fixture()

      assert Lightning.Policies.Permissions.can(
               Lightning.Policies.UserPolicy,
               :create_projects,
               superuser,
               {}
             )
    end
  end

  describe "Projects membership policies" do
    test "project viewers can't edit jobs" do
      user = user_fixture()

      project =
        project_fixture(project_users: [%{user_id: user.id, role: :viewer}])

      refute Lightning.Policies.Permissions.can(
               Lightning.Policies.MemberPolicy,
               :edit_jobs,
               user,
               project
             )
    end

    test "project admins, editors, and owners can edit jobs" do
      admin = user_fixture()
      editor = user_fixture()
      owner = user_fixture()

      project =
        project_fixture(
          project_users: [
            %{user_id: owner.id, role: :owner},
            %{user_id: admin.id, role: :admin},
            %{user_id: editor.id, role: :editor}
          ]
        )

      assert Lightning.Policies.Permissions.can(
               Lightning.Policies.MemberPolicy,
               :edit_jobs,
               admin,
               project
             )

      assert Lightning.Policies.Permissions.can(
               Lightning.Policies.MemberPolicy,
               :edit_jobs,
               owner,
               project
             )

      assert Lightning.Policies.Permissions.can(
               Lightning.Policies.MemberPolicy,
               :edit_jobs,
               editor,
               project
             )
    end
  end
end
