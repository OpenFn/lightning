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

  describe "connect_github_repo/3" do
    setup do
      Tesla.Mock.mock(fn env ->
        case env.url do
          "https://api.github.com/app/installations/some-id/access_tokens" ->
            %Tesla.Env{status: 201, body: %{"token" => "some-token"}}

          # create blob
          "https://api.github.com/repos/some/repo/git/blobs" ->
            %Tesla.Env{
              status: 201,
              body: %{"sha" => "3a0f86fb8db8eea7ccbb9a95f325ddbedfb25e15"}
            }

          # get commit on master branch
          "https://api.github.com/repos/some/repo/commits/heads/master" ->
            %Tesla.Env{
              status: 200,
              body: %{
                "sha" => "6dcb09b5b57875f334f61aebed695e2e4193db5e",
                "commit" => %{
                  "tree" => %{
                    "sha" => "6dcb09b5b57875f334f61aebed695e2e4193db5e"
                  }
                }
              }
            }

          # create commit
          "https://api.github.com/repos/some/repo/git/commits" ->
            %Tesla.Env{
              status: 201,
              body: %{"sha" => "7638417db6d59f3c431d3e1f261cc637155684cd"}
            }

          # create tree
          "https://api.github.com/repos/some/repo/git/trees" ->
            %Tesla.Env{
              status: 201,
              body: %{"sha" => "cd8274d15fa3ae2ab983129fb037999f264ba9a7"}
            }

          # update a reference. in this case, the master branch
          "https://api.github.com/repos/some/repo/git/refs/heads/master" ->
            %Tesla.Env{
              status: 200,
              body: %{"ref" => "refs/heads/master"}
            }
        end
      end)

      :ok
    end

    test "given a project_id, branch and repo it should update a connection" do
      project = insert(:project)
      user = insert(:user)

      assert Repo.aggregate(ProjectRepoConnection, :count) == 0

      insert(:project_repo_connection, %{
        project: project,
        user: user,
        github_installation_id: "some-id",
        branch: nil,
        repo: nil
      })

      assert Repo.aggregate(ProjectRepoConnection, :count) == 1

      assert {:ok, updated_connection} =
               VersionControl.connect_github_repo(
                 project.id,
                 "some/repo",
                 "master"
               )

      assert updated_connection.project_id == project.id
      assert updated_connection.branch == "master"
      assert updated_connection.repo == "some/repo"
    end
  end
end
