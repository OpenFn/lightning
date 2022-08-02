defmodule Lightning.Projects.PolicyTest do
  use Lightning.DataCase, async: true

  alias Lightning.Accounts.User
  import Lightning.ProjectsFixtures
  import Lightning.AccountsFixtures

  describe "Projects policy" do
    test "users can't access projects they aren't members of" do
      user = user_fixture()
      project = project_fixture(project_users: [%{user_id: user.id}])

      assert :ok =
               Bodyguard.permit(Lightning.Projects.Policy, :read, user, project)

      other_project = project_fixture(project_users: [])

      assert {:error, :unauthorized} =
               Bodyguard.permit(
                 Lightning.Projects.Policy,
                 :read,
                 user,
                 other_project
               )
    end

    test "regular users can't do anything" do
      assert {:error, :unauthorized} =
               Bodyguard.permit(Lightning.Projects.Policy, :index, %User{
                 role: :user
               })
    end

    test "super users can access user management page" do
      assert :ok =
               Bodyguard.permit(Lightning.Projects.Policy, :index, %User{
                 role: :superuser
               })
    end
  end
end
