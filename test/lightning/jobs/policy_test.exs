defmodule Lightning.Jobs.PolicyTest do
  use Lightning.DataCase, async: true

  alias Lightning.Accounts.User
  import Lightning.ProjectsFixtures
  import Lightning.AccountsFixtures

  test "users can't list jobs for project they aren't members of" do
    user = user_fixture()
    project = project_fixture(project_users: [%{user_id: user.id}])

    assert :ok = Bodyguard.permit(Lightning.Jobs.Policy, :list, user, project)
  end

  test "default is to deny access" do
    assert {:error, :unauthorized} =
             Bodyguard.permit(Lightning.Jobs.Policy, :index, %User{
               role: :user
             })
  end
end
