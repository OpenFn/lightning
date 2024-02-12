defmodule Lightning.VersionControlTest do
  use Lightning.DataCase, async: true
  alias Lightning.VersionControl
  alias Lightning.VersionControl.ProjectRepoConnection
  alias Lightning.Repo

  import Lightning.Factories

  describe "Version Control" do
    test "deletes a project repo connection" do
      project_repo_connection = insert(:project_repo_connection)
      assert Repo.aggregate(ProjectRepoConnection, :count, :id) == 1

      assert {:ok, _} =
               VersionControl.remove_github_connection(
                 project_repo_connection.project_id
               )

      assert Repo.aggregate(ProjectRepoConnection, :count, :id) == 0
    end

    test "fetches a project repo using a project id" do
      project_repo_connection = insert(:project_repo_connection)

      assert %ProjectRepoConnection{} =
               VersionControl.get_repo_connection(
                 project_repo_connection.project_id
               )
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

    test "create_github_connection/1 errors out when the user has an existing pending connection" do
      project1 = insert(:project)
      project2 = insert(:project)
      user = insert(:user)

      # insert existing installation
      insert(:project_repo_connection, %{
        project: project1,
        user: user,
        repo: nil,
        branch: nil,
        github_installation_id: nil
      })

      attrs = %{
        project_id: project2.id,
        user_id: user.id
      }

      assert {:error, changeset} =
               VersionControl.create_github_connection(attrs)

      assert changeset.errors == [
               {:user_id, {"user has pending installation", []}}
             ]
    end

    test "given a project_id, branch and repo it should update a connection" do
      project = insert(:project)
      user = insert(:user)

      attrs = %{project_id: project.id, user_id: user.id}

      assert Repo.aggregate(ProjectRepoConnection, :count) == 0

      VersionControl.create_github_connection(attrs)

      assert Repo.aggregate(ProjectRepoConnection, :count) == 1

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

    test "add_github_installation_id/2 updates the installation_id for the correct project for the given user" do
      project1 = insert(:project)
      project2 = insert(:project)
      user = insert(:user)

      {:ok, _connection1} =
        VersionControl.create_github_connection(%{
          project_id: project1.id,
          user_id: user.id,
          github_installation_id: "some-id"
        })

      {:ok, connection2} =
        VersionControl.create_github_connection(%{
          project_id: project2.id,
          user_id: user.id
        })

      {:ok, updated_connection} =
        VersionControl.add_github_installation_id(
          user.id,
          "some_installation"
        )

      assert updated_connection.id == connection2.id
    end

    test "add_github_installation_id/2 raises when you there's no pending installation" do
      project1 = insert(:project)
      user = insert(:user)

      {:ok, _connection1} =
        VersionControl.create_github_connection(%{
          project_id: project1.id,
          user_id: user.id,
          github_installation_id: "some-id"
        })

      assert_raise Ecto.NoResultsError, fn ->
        VersionControl.add_github_installation_id(
          user.id,
          "some_installation"
        )
      end
    end
  end
end
