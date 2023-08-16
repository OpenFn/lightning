defmodule Lightning.VersionControlTest do
  use Lightning.DataCase, async: true
  alias Lightning.VersionControl
  alias Lightning.VersionControl.ProjectRepo
  alias Lightning.Repo

  import Lightning.Factories

  describe "Version Control" do
    test "deletes a project repo connection" do
      project_repo = insert(:project_repo)
      assert Repo.aggregate(ProjectRepo, :count, :id) == 1

      assert {:ok, _} =
               VersionControl.remove_github_connection(project_repo.project_id)

      assert Repo.aggregate(ProjectRepo, :count, :id) == 0
    end

    test "fetches a project repo using a project id" do
      project_repo = insert(:project_repo)

      assert %ProjectRepo{} =
               VersionControl.get_repo_connection(project_repo.project_id)
    end

    test "creates a project github repo connection record when project and user id are present" do
      project = insert(:project)
      user = insert(:user)

      attrs = %{
        project_id: project.id,
        user_id: user.id
      }

      assert {:ok, repo_connection} =
               VersionControl.create_github_connection(attrs)

      assert repo_connection.project_id == project.id
    end

    test "given a project_id, branch and repo it should update a connection" do
      project = insert(:project)
      user = insert(:user)

      attrs = %{project_id: project.id, user_id: user.id}

      assert Repo.aggregate(ProjectRepo, :count) == 0

      VersionControl.create_github_connection(attrs)

      assert Repo.aggregate(ProjectRepo, :count) == 1

      assert {:ok, updated_connection} =
               VersionControl.add_github_repo_and_branch(
                 project.id,
                 "some_repo",
                 "some_branch"
               )

      assert updated_connection.project_id == project.id
      assert updated_connection.branch == "some_branch"
      assert updated_connection.repo == "some_repo"
    end

    test "given a user_id and a installation_id it should update the correct record" do
      project = insert(:project)
      [u1, u2] = insert_pair(:user)

      attrs1 = %{project_id: project.id, user_id: u1.id}

      attrs2 = %{project_id: project.id, user_id: u2.id}

      assert Repo.aggregate(ProjectRepo, :count) == 0

      Enum.each([attrs1, attrs2], &VersionControl.create_github_connection/1)

      assert Repo.aggregate(ProjectRepo, :count) == 2

      assert {:ok, updated_connection} =
               VersionControl.add_github_installation_id(
                 u1.id,
                 "some_installation"
               )

      assert updated_connection.user_id == u1.id

      not_updated = Repo.get_by(ProjectRepo, user_id: u2.id)

      refute not_updated.id == updated_connection.id
      refute not_updated.github_installation_id
    end
  end
end
