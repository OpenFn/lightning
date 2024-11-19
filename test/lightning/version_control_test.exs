defmodule Lightning.VersionControlTest do
  use Lightning.DataCase, async: true

  alias Lightning.Auditing.Audit
  alias Lightning.Repo
  alias Lightning.VersionControl
  alias Lightning.VersionControl.ProjectRepoConnection
  alias Lightning.Workflows.Snapshot

  import Lightning.Factories

  import Lightning.GithubHelpers
  import Mox

  describe "create_github_connection/2" do
    test "user with valid oauth token creates connection successfully" do
      Mox.verify_on_exit!()
      project = insert(:project)
      user = user_with_valid_github_oauth()

      assert Repo.aggregate(ProjectRepoConnection, :count) == 0

      expected_installation = %{
        "id" => "1234",
        "account" => %{
          "type" => "User",
          "login" => "username"
        }
      }

      expected_repo = %{
        "full_name" => "someaccount/somerepo",
        "default_branch" => "main"
      }

      expected_branch = %{"name" => "somebranch"}

      # push pull.yml
      expect_get_repo(expected_repo["full_name"], 200, expected_repo)
      expect_create_blob(expected_repo["full_name"])

      expect_get_commit(
        expected_repo["full_name"],
        expected_repo["default_branch"]
      )

      expect_create_tree(expected_repo["full_name"])
      expect_create_commit(expected_repo["full_name"])

      expect_update_ref(
        expected_repo["full_name"],
        expected_repo["default_branch"]
      )

      # push deploy.yml + config.json
      # deploy.yml blob
      expect_create_blob(expected_repo["full_name"])
      # config.json blob
      expect_create_blob(expected_repo["full_name"])
      expect_get_commit(expected_repo["full_name"], expected_branch["name"])
      expect_create_tree(expected_repo["full_name"])
      expect_create_commit(expected_repo["full_name"])
      expect_update_ref(expected_repo["full_name"], expected_branch["name"])

      # write secret
      expect_get_public_key(expected_repo["full_name"])
      secret_name = "OPENFN_#{String.replace(project.id, "-", "_")}_API_KEY"
      expect_create_repo_secret(expected_repo["full_name"], secret_name)

      # initialize sync
      expect_create_installation_token(expected_installation["id"])
      expect_get_repo(expected_repo["full_name"], 200, expected_repo)

      expect_create_workflow_dispatch(
        expected_repo["full_name"],
        "openfn-pull.yml"
      )

      params = %{
        "project_id" => project.id,
        "repo" => expected_repo["full_name"],
        "branch" => expected_branch["name"],
        "github_installation_id" => expected_installation["id"],
        "sync_direction" => "pull",
        "accept" => "true"
      }

      now = DateTime.utc_now()
      current_time_in_unix = now |> DateTime.to_unix()

      Lightning.Stub.freeze_time(now)

      assert {:ok, repo_connection} =
               VersionControl.create_github_connection(
                 params,
                 user
               )

      {:ok, claims} =
        ProjectRepoConnection.AccessToken.verify_and_validate(
          repo_connection.access_token,
          Lightning.Config.repo_connection_token_signer()
        )

      project_id = project.id

      assert %{
               "project_id" => ^project_id,
               "iss" => "Lightning",
               "nbf" => ^current_time_in_unix,
               "iat" => ^current_time_in_unix,
               "jti" => jti
             } = claims

      assert is_binary(jti)

      assert Repo.aggregate(ProjectRepoConnection, :count) == 1

      assert repo_connection.project_id == project.id
      assert repo_connection.branch == params["branch"]
      assert repo_connection.repo == params["repo"]

      assert repo_connection.github_installation_id ==
               params["github_installation_id"]
    end

    test "creating the repo connection creates an audit entry" do
      %{id: project_id} = insert(:project)
      %{id: user_id} = user = user_with_valid_github_oauth()

      repo = "someaccount/somerepo"
      branch = "somebranch"
      github_installation_id = "1234"

      expected_installation = %{
        "id" => github_installation_id,
        "account" => %{
          "type" => "User",
          "login" => "username"
        }
      }

      expected_repo = %{
        "full_name" => repo,
        "default_branch" => "main"
      }

      expected_branch = %{"name" => branch}

      # push pull.yml
      expect_get_repo(expected_repo["full_name"], 200, expected_repo)
      expect_create_blob(expected_repo["full_name"])

      expect_get_commit(
        expected_repo["full_name"],
        expected_repo["default_branch"]
      )

      expect_create_tree(expected_repo["full_name"])
      expect_create_commit(expected_repo["full_name"])

      expect_update_ref(
        expected_repo["full_name"],
        expected_repo["default_branch"]
      )

      # push deploy.yml + config.json
      # deploy.yml blob
      expect_create_blob(expected_repo["full_name"])
      # config.json blob
      expect_create_blob(expected_repo["full_name"])
      expect_get_commit(expected_repo["full_name"], expected_branch["name"])
      expect_create_tree(expected_repo["full_name"])
      expect_create_commit(expected_repo["full_name"])
      expect_update_ref(expected_repo["full_name"], expected_branch["name"])

      # write secret
      expect_get_public_key(expected_repo["full_name"])
      secret_name = "OPENFN_#{String.replace(project_id, "-", "_")}_API_KEY"
      expect_create_repo_secret(expected_repo["full_name"], secret_name)

      # initialize sync
      expect_create_installation_token(expected_installation["id"])
      expect_get_repo(expected_repo["full_name"], 200, expected_repo)

      expect_create_workflow_dispatch(
        expected_repo["full_name"],
        "openfn-pull.yml"
      )

      params = %{
        "project_id" => project_id,
        "repo" => repo,
        "branch" => branch,
        "github_installation_id" => github_installation_id,
        "sync_direction" => "pull",
        "accept" => "true"
      }

      {:ok, %{id: _repo_connection_id}} =
        VersionControl.create_github_connection(params, user)

      audit = Repo.one!(Audit)

      assert %{
               event: "repo_connection_created",
               item_id: ^project_id,
               item_type: "project",
               actor_id: ^user_id,
               changes: %{
                 after: %{
                   "repo" => ^repo,
                   "branch" => ^branch,
                   "sync_direction" => "pull"
                 }
               }
             } = audit
    end

    test "user without an oauth token cannot create a repo connection" do
      project = insert(:project)
      user = insert(:user)

      assert Repo.aggregate(ProjectRepoConnection, :count) == 0

      params = %{
        "project_id" => project.id,
        "repo" => "some/repo",
        "branch" => "somebranch",
        "github_installation_id" => "1234"
      }

      assert {:error, _error} =
               VersionControl.create_github_connection(
                 params,
                 user
               )

      assert Repo.aggregate(ProjectRepoConnection, :count) == 0
    end
  end

  describe "remove_github_connection/2" do
    test "user with a valid oauth token can successfully remove a connection" do
      Mox.verify_on_exit!()
      project = insert(:project)
      user = user_with_valid_github_oauth()

      repo_connection =
        insert(:project_repo_connection,
          project: project,
          repo: "someaccount/somerepo",
          branch: "somebranch",
          github_installation_id: "1234",
          access_token: "someaccesstoken"
        )

      assert is_map(user.github_oauth_token)

      # check if deploy yml exists for deletion
      expected_deploy_yml_path =
        ".github/workflows/openfn-#{project.id}-deploy.yml"

      expect_get_repo_content(repo_connection.repo, expected_deploy_yml_path)

      # deletes successfully
      expect_delete_repo_content(
        repo_connection.repo,
        expected_deploy_yml_path
      )

      # check if deploy yml exists for deletion
      expected_config_json_path = "openfn-#{project.id}-config.json"
      expect_get_repo_content(repo_connection.repo, expected_config_json_path)
      # fails to delete
      expect_delete_repo_content(
        repo_connection.repo,
        expected_config_json_path,
        400,
        %{"something" => "happened"}
      )

      # delete secret
      expect_delete_repo_secret(
        repo_connection.repo,
        "OPENFN_#{String.replace(project.id, "-", "_")}_API_KEY"
      )

      assert Repo.aggregate(ProjectRepoConnection, :count) == 1

      assert {:ok, _connection} =
               VersionControl.remove_github_connection(
                 repo_connection,
                 user
               )

      assert Repo.aggregate(ProjectRepoConnection, :count) == 0
    end

    test "user without an oauth token can successfully remove a connection" do
      project = insert(:project)
      user = insert(:user)

      repo_connection =
        insert(:project_repo_connection,
          project: project,
          repo: "someaccount/somerepo",
          branch: "somebranch",
          github_installation_id: "1234",
          access_token: "someaccesstoken"
        )

      assert is_nil(user.github_oauth_token)

      assert Repo.aggregate(ProjectRepoConnection, :count) == 1

      assert {:ok, _connection} =
               VersionControl.remove_github_connection(
                 repo_connection,
                 user
               )

      assert Repo.aggregate(ProjectRepoConnection, :count) == 0
    end
  end

  describe "exchange_code_for_oauth_token/1" do
    test "returns ok for a response body with access_token" do
      expected_token = %{"access_token" => "1234567"}

      Mox.expect(Lightning.Tesla.Mock, :call, fn
        %{url: "https://github.com/login/oauth/access_token"}, _opts ->
          {:ok, %Tesla.Env{body: expected_token}}
      end)

      assert {:ok, ^expected_token} =
               VersionControl.exchange_code_for_oauth_token("some-code")
    end

    test "returns error for a response body without access_token" do
      expected_token = %{"something" => "else"}

      Mox.expect(Lightning.Tesla.Mock, :call, fn
        %{url: "https://github.com/login/oauth/access_token"}, _opts ->
          {:ok, %Tesla.Env{body: expected_token}}
      end)

      assert {:error, ^expected_token} =
               VersionControl.exchange_code_for_oauth_token("some-code")
    end
  end

  describe "refresh_oauth_token/1" do
    test "returns ok for a response body with access_token" do
      expected_token = %{"access_token" => "1234567"}

      Mox.expect(Lightning.Tesla.Mock, :call, fn
        %{url: "https://github.com/login/oauth/access_token"}, _opts ->
          {:ok, %Tesla.Env{body: expected_token}}
      end)

      assert {:ok, ^expected_token} =
               VersionControl.refresh_oauth_token("some-token")
    end

    test "returns error for a response body without access_token" do
      expected_token = %{"something" => "else"}

      Mox.expect(Lightning.Tesla.Mock, :call, fn
        %{url: "https://github.com/login/oauth/access_token"}, _opts ->
          {:ok, %Tesla.Env{body: expected_token}}
      end)

      assert {:error, ^expected_token} =
               VersionControl.refresh_oauth_token("some-token")
    end
  end

  describe "fetch_user_access_token/1" do
    test "returns ok for an access token that is still active" do
      active_token = %{
        "access_token" => "access-token",
        "refresh_token" => "refresh-token",
        "expires_at" => DateTime.utc_now() |> DateTime.add(20),
        "refresh_token_expires_at" => DateTime.utc_now() |> DateTime.add(20)
      }

      # reload so that we can get the token as they are from the db
      user =
        insert(:user, github_oauth_token: active_token)
        |> Lightning.Repo.reload!()

      expected_token = active_token["access_token"]

      assert {:ok, ^expected_token} =
               VersionControl.fetch_user_access_token(user)
    end

    test "returns ok for an access token that has no expiry" do
      active_token = %{"access_token" => "access-token"}

      user = insert(:user, github_oauth_token: active_token)

      expected_token = active_token["access_token"]

      assert {:ok, ^expected_token} =
               VersionControl.fetch_user_access_token(user)
    end

    test "refreshes the access_token if it has expired and updates the user info" do
      active_token = %{
        "access_token" => "access-token",
        "refresh_token" => "refresh-token",
        "expires_at" => DateTime.utc_now() |> DateTime.add(-20),
        "refresh_token_expires_at" => DateTime.utc_now() |> DateTime.add(100)
      }

      # reload so that we can get the token as they are from the db
      user =
        insert(:user, github_oauth_token: active_token)
        |> Lightning.Repo.reload!()

      assert user.github_oauth_token["access_token"] ==
               active_token["access_token"]

      expected_access_token = "updated-access-token"

      Mox.expect(Lightning.Tesla.Mock, :call, fn
        %{url: "https://github.com/login/oauth/access_token"}, _opts ->
          {:ok, %Tesla.Env{body: %{"access_token" => expected_access_token}}}
      end)

      assert {:ok, ^expected_access_token} =
               VersionControl.fetch_user_access_token(user)

      updated_user = Lightning.Repo.reload!(user)

      assert updated_user.github_oauth_token["access_token"] ==
               expected_access_token
    end
  end

  describe "save_oauth_token/2" do
    test "adds expiry dates to the token if needed" do
      user = insert(:user)

      token = %{
        "access_token" => "access-token",
        "refresh_token" => "refresh-token",
        "expires_in" => 3600,
        "refresh_token_expires_in" => 7200
      }

      {:ok, updated_user} = VersionControl.save_oauth_token(user, token)

      expected_access_token_expiry =
        DateTime.utc_now()
        |> DateTime.add(token["expires_in"])

      expected_refresh_token_expiry =
        DateTime.utc_now()
        |> DateTime.add(token["refresh_token_expires_in"])

      # https://hexdocs.pm/timex/Timex.html#compare/3
      # comparing to second precision
      assert Timex.compare(
               updated_user.github_oauth_token["expires_at"],
               expected_access_token_expiry,
               :seconds
             ) == 0

      assert Timex.compare(
               updated_user.github_oauth_token["refresh_token_expires_at"],
               expected_refresh_token_expiry,
               :seconds
             ) == 0
    end

    test "does not add expiry dates if none is needed" do
      user = insert(:user)

      token = %{"access_token" => "access-token"}

      {:ok, updated_user} = VersionControl.save_oauth_token(user, token)

      assert updated_user.github_oauth_token == %{
               "access_token" => "access-token"
             }
    end
  end

  describe "initiate_sync/2" do
    setup do
      verify_on_exit!()

      project = insert(:project)
      workflow = insert(:simple_workflow, project: project)
      user = user_with_valid_github_oauth()
      repo_connection = insert(:project_repo_connection, project: project)

      [
        project: project,
        user: user,
        repo_connection: repo_connection,
        workflow: workflow
      ]
    end

    test "creates snapshots for workflows without snapshots", %{
      user: user,
      repo_connection: repo_connection,
      workflow: workflow
    } do
      refute Snapshot.get_current_for(workflow)

      expect_create_installation_token(repo_connection.github_installation_id)
      expect_get_repo(repo_connection.repo)
      expect_create_workflow_dispatch(repo_connection.repo, "openfn-pull.yml")

      assert :ok = VersionControl.initiate_sync(repo_connection, user.email)
      assert Snapshot.get_current_for(workflow)
    end

    test "creates audit entries for any snapshots created", %{
      user: user,
      repo_connection: %{id: repo_connection_id} = repo_connection,
      workflow: %{id: workflow_id} = workflow
    } do
      expect_create_installation_token(repo_connection.github_installation_id)
      expect_get_repo(repo_connection.repo)
      expect_create_workflow_dispatch(repo_connection.repo, "openfn-pull.yml")

      assert :ok = VersionControl.initiate_sync(repo_connection, user.email)

      %{id: snapshot_id} = Snapshot.get_current_for(workflow)

      audit = Audit |> Repo.one!()

      assert %{
               event: "snapshot_created",
               item_id: ^workflow_id,
               actor_id: ^repo_connection_id,
               changes: %{
                 after: %{"snapshot_id" => ^snapshot_id}
               }
             } = audit
    end
  end

  defp user_with_valid_github_oauth do
    active_token = %{
      "access_token" => "access-token",
      "refresh_token" => "refresh-token",
      "expires_at" => DateTime.utc_now() |> DateTime.add(500),
      "refresh_token_expires_at" => DateTime.utc_now() |> DateTime.add(500)
    }

    insert(:user, github_oauth_token: active_token) |> Lightning.Repo.reload()
  end
end
