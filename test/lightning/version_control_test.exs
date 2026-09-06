defmodule Lightning.VersionControlTest do
  use Lightning.DataCase, async: true

  alias Lightning.Auditing.Audit
  alias Lightning.Extensions.MockUsageLimiter
  alias Lightning.Extensions.Message
  alias Lightning.Extensions.UsageLimiting.Action
  alias Lightning.Extensions.UsageLimiting.Context
  alias Lightning.Repo
  alias Lightning.VersionControl
  alias Lightning.VersionControl.ProjectRepoConnection
  alias Lightning.Workflows.Snapshot

  import ExUnit.CaptureLog
  import Lightning.Factories

  import Lightning.GithubHelpers
  import Mox

  setup :verify_on_exit!

  describe "create_github_connection/2" do
    test "user with valid oauth token creates connection successfully" do
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

      expect_full_github_connection_flow(
        expected_repo,
        expected_branch["name"],
        project.id,
        expected_installation["id"]
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

      expect_full_github_connection_flow(
        expected_repo,
        expected_branch["name"],
        project_id,
        expected_installation["id"]
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

    test "audits the removal of the repo connection" do
      %{id: project_id} = project = insert(:project)
      %{id: user_id} = user = user_with_valid_github_oauth()

      repo = "someaccount/somerepo"
      branch = "somebranch"

      repo_connection =
        insert(:project_repo_connection,
          project: project,
          repo: repo,
          branch: branch,
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

      VersionControl.remove_github_connection(repo_connection, user)

      audit = Repo.one!(Audit)

      assert %{
               event: "repo_connection_removed",
               item_id: ^project_id,
               item_type: "project",
               actor_id: ^user_id,
               changes: %{
                 before: %{
                   "repo" => ^repo,
                   "branch" => ^branch
                 }
               }
             } = audit
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
      user = user_with_valid_github_oauth()

      assert {:ok, "access-token"} = VersionControl.fetch_user_access_token(user)
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
      project = insert(:project)

      workflow = insert(:simple_workflow, project: project)
      {:ok, snapshot} = Snapshot.create(workflow)

      other_workflow = insert(:simple_workflow, project: project)
      {:ok, other_snapshot} = Snapshot.create(other_workflow)

      repo_connection = insert(:project_repo_connection, project: project)

      [
        commit_message: "my little commit message",
        project: project,
        repo_connection: repo_connection,
        snapshots: [snapshot, other_snapshot],
        workflow: workflow
      ]
    end

    test "checks if github sync is rate limited", %{
      commit_message: commit_message,
      project: %{id: project_id},
      repo_connection: repo_connection
    } do
      action = %Action{type: :github_sync}
      context = %Context{project_id: project_id}

      Mox.expect(MockUsageLimiter, :limit_action, fn ^action, ^context ->
        :ok
      end)

      expect_create_installation_token(repo_connection.github_installation_id)
      expect_get_repo(repo_connection.repo)
      expect_create_workflow_dispatch(repo_connection.repo, "openfn-pull.yml")

      VersionControl.initiate_sync(repo_connection, commit_message)
    end

    test "returns error if github sync is rate limited", %{
      commit_message: commit_message,
      project: %{id: project_id},
      repo_connection: repo_connection
    } do
      action = %Action{type: :github_sync}
      context = %Context{project_id: project_id}

      message = %Message{text: "You melted the CPU."}

      Mox.stub(MockUsageLimiter, :limit_action, fn ^action, ^context ->
        {:error, :melted, message}
      end)

      assert {:error, ^message} =
               VersionControl.initiate_sync(repo_connection, commit_message)
    end

    test "creates GH workflow dispatch event using JSON config (default)", %{
      commit_message: commit_message,
      repo_connection: repo_connection,
      snapshots: [snapshot, other_snapshot]
    } do
      expect_create_installation_token(repo_connection.github_installation_id)
      expect_get_repo(repo_connection.repo)

      expect_workflow_dispatch_with_snapshots(
        repo_connection,
        commit_message,
        [snapshot.id, other_snapshot.id]
      )

      assert :ok = VersionControl.initiate_sync(repo_connection, commit_message)
    end

    test "creates GH workflow dispatch event using YAML config (sync_version: true)",
         %{
           commit_message: commit_message,
           repo_connection: repo_connection,
           snapshots: [snapshot, other_snapshot]
         } do
      yaml_connection =
        repo_connection
        |> Ecto.Changeset.change(sync_version: true)
        |> Lightning.Repo.update!()

      expect_create_installation_token(yaml_connection.github_installation_id)
      expect_get_repo(yaml_connection.repo)

      expect_workflow_dispatch_with_snapshots(
        yaml_connection,
        commit_message,
        [snapshot.id, other_snapshot.id]
      )

      assert :ok = VersionControl.initiate_sync(yaml_connection, commit_message)
    end

    defp api_secret_name(%{project_id: project_id}) do
      project_id
      |> String.replace("-", "_")
      |> then(&"OPENFN_#{&1}_API_KEY")
    end

    defp path_to_config(repo_connection) do
      ProjectRepoConnection.config_path(repo_connection)
      |> Path.relative_to(".")
    end

    # list_snapshots_for_project/1 doesn't order its query, so the
    # snapshots ids can arrive in either order; assert the set, not a
    # sequence.
    defp expect_workflow_dispatch_with_snapshots(
           repo_connection,
           commit_message,
           snapshot_ids
         ) do
      repo = repo_connection.repo

      Mox.expect(Lightning.Tesla.Mock, :call, fn %{
                                                   url:
                                                     "https://api.github.com/repos/" <>
                                                       ^repo <>
                                                       "/actions/workflows/openfn-pull.yml/dispatches",
                                                   body: body
                                                 },
                                                 _opts ->
        decoded = Jason.decode!(body)
        inputs = decoded["inputs"]

        assert decoded["ref"] == "main"

        assert inputs["snapshots"] |> String.split() |> Enum.sort() ==
                 Enum.sort(snapshot_ids)

        assert Map.delete(inputs, "snapshots") == %{
                 "projectId" => repo_connection.project_id,
                 "apiSecretName" => api_secret_name(repo_connection),
                 "branch" => repo_connection.branch,
                 "pathToConfig" => path_to_config(repo_connection),
                 "commitMessage" => commit_message
               }

        {:ok, %Tesla.Env{status: 204, body: ""}}
      end)
    end
  end

  describe "fetch_installation_repos/1" do
    test "returns correct result when repos are less than 100" do
      installation_id = 1234

      repos =
        Enum.map(1..30, fn n ->
          %{"full_name" => "account/repo#{n}", "default_branch" => "main"}
        end)

      expect_create_installation_token(installation_id)

      expected_result = %{
        "total_count" => Enum.count(repos),
        "repositories" => repos
      }

      expect_get_installation_repos(200, expected_result)

      assert {:ok, ^expected_result} =
               VersionControl.fetch_installation_repos(installation_id)
    end

    test "returns correct result when repos are more than 100" do
      installation_id = 1234

      first_100_repos =
        Enum.map(1..100, fn n ->
          %{"full_name" => "account/repo#{n}", "default_branch" => "main"}
        end)

      next_batch =
        Enum.map(101..183, fn n ->
          %{"full_name" => "account/repo#{n}", "default_branch" => "main"}
        end)

      expected_repos = next_batch ++ first_100_repos

      expect_create_installation_token(installation_id)

      expect(Lightning.Tesla.Mock, :call, 2, fn %{
                                                  url:
                                                    "https://api.github.com/installation/repositories",
                                                  query: [
                                                    page: page,
                                                    per_page: 100
                                                  ]
                                                },
                                                _opts ->
        repositories = if page == 1, do: first_100_repos, else: next_batch

        {:ok,
         %Tesla.Env{
           status: 200,
           body: %{
             "total_count" => Enum.count(expected_repos),
             "repositories" => repositories
           }
         }}
      end)

      expected_result = %{
        "total_count" => Enum.count(expected_repos),
        "repositories" => expected_repos
      }

      assert {:ok, ^expected_result} =
               VersionControl.fetch_installation_repos(installation_id)
    end

    test "result is returned even when subsequent calls fail" do
      installation_id = 1234

      first_100_repos =
        Enum.map(1..100, fn n ->
          %{"full_name" => "account/repo#{n}", "default_branch" => "main"}
        end)

      next_100_repos =
        Enum.map(101..200, fn n ->
          %{"full_name" => "account/repo#{n}", "default_branch" => "main"}
        end)

      last_batch =
        Enum.map(201..230, fn n ->
          %{"full_name" => "account/repo#{n}", "default_branch" => "main"}
        end)

      total_repo_count =
        Enum.count(first_100_repos ++ next_100_repos ++ last_batch)

      expected_repos = last_batch ++ first_100_repos

      expect_create_installation_token(installation_id)

      expect(Lightning.Tesla.Mock, :call, 3, fn %{
                                                  url:
                                                    "https://api.github.com/installation/repositories",
                                                  query: [
                                                    page: page,
                                                    per_page: 100
                                                  ]
                                                },
                                                _opts ->
        case page do
          1 ->
            {:ok,
             %Tesla.Env{
               status: 200,
               body: %{
                 "total_count" => total_repo_count,
                 "repositories" => first_100_repos
               }
             }}

          2 ->
            # We're failing to return the 2nd batch
            {:ok,
             %Tesla.Env{
               status: 403,
               body: %{"message" => "some error maybe spike"}
             }}

          3 ->
            {:ok,
             %Tesla.Env{
               status: 200,
               body: %{
                 "total_count" => total_repo_count,
                 "repositories" => last_batch
               }
             }}
        end
      end)

      expected_result = %{
        "total_count" => total_repo_count,
        "repositories" => expected_repos
      }

      {result, log} =
        with_log([level: :error], fn ->
          VersionControl.fetch_installation_repos(installation_id)
        end)

      assert {:ok, ^expected_result} = result

      assert log =~ "Failed to fetch a subsequent github repositories page"
    end
  end

  describe "config file blob content" do
    setup do
      project = insert(:project)
      user = user_with_valid_github_oauth()

      repo = "someaccount/somerepo"
      branch = "somebranch"
      installation_id = "1234"

      base_params = %{
        "project_id" => project.id,
        "repo" => repo,
        "branch" => branch,
        "github_installation_id" => installation_id,
        "sync_direction" => "pull",
        "accept" => "true"
      }

      expected_repo = %{"full_name" => repo, "default_branch" => "main"}

      {:ok,
       project: project,
       user: user,
       repo: repo,
       branch: branch,
       installation_id: installation_id,
       base_params: base_params,
       expected_repo: expected_repo}
    end

    test "pushes JSON config blob when sync_version is false (default)", %{
      project: project,
      user: user,
      repo: repo,
      branch: branch,
      installation_id: installation_id,
      base_params: base_params,
      expected_repo: expected_repo
    } do
      expect_full_github_connection_flow(
        expected_repo,
        branch,
        project.id,
        installation_id,
        config_blob_expectation: fn ->
          Mox.expect(Lightning.Tesla.Mock, :call, fn env, _opts ->
            assert env.url == "https://api.github.com/repos/#{repo}/git/blobs"
            body = Jason.decode!(env.body)

            assert body["content"] =~
                     "\"statePath\": \"openfn-#{project.id}-state.json\""

            assert body["content"] =~
                     "\"specPath\": \"openfn-#{project.id}-spec.yaml\""

            {:ok, %Tesla.Env{status: 201, body: %{"sha" => "3a0f8"}}}
          end)
        end
      )

      assert {:ok, _} =
               VersionControl.create_github_connection(base_params, user)
    end

    test "pushes YAML config blob when sync_version is true", %{
      project: project,
      user: user,
      repo: repo,
      branch: branch,
      installation_id: installation_id,
      base_params: base_params,
      expected_repo: expected_repo
    } do
      expect_full_github_connection_flow(
        expected_repo,
        branch,
        project.id,
        installation_id,
        config_blob_expectation: fn ->
          Mox.expect(Lightning.Tesla.Mock, :call, fn env, _opts ->
            assert env.url == "https://api.github.com/repos/#{repo}/git/blobs"
            body = Jason.decode!(env.body)
            assert body["content"] =~ "project:"
            assert body["content"] =~ "uuid: #{project.id}"
            assert body["content"] =~ LightningWeb.Endpoint.url()
            {:ok, %Tesla.Env{status: 201, body: %{"sha" => "3a0f8"}}}
          end)
        end
      )

      params = Map.put(base_params, "sync_version", "true")
      assert {:ok, _} = VersionControl.create_github_connection(params, user)
    end
  end

  # These 17 expectations share one Mox FIFO queue on the same mocked
  # function, so registration order here must match the call order
  # create_github_connection/2 actually makes.
  #
  # `config_blob_expectation` overrides the config.json blob call (the 8th
  # of the 17) for tests that assert on its request body; it defaults to
  # the plain expect_create_blob/1 behaviour.
  defp expect_full_github_connection_flow(
         expected_repo,
         branch,
         project_id,
         installation_id,
         opts \\ []
       ) do
    repo = expected_repo["full_name"]
    default_branch = expected_repo["default_branch"]

    config_blob_expectation =
      Keyword.get(opts, :config_blob_expectation, fn ->
        expect_create_blob(repo)
      end)

    # push pull.yml
    expect_get_repo(repo, 200, expected_repo)
    expect_create_blob(repo)
    expect_get_commit(repo, default_branch)
    expect_create_tree(repo)
    expect_create_commit(repo)
    expect_update_ref(repo, default_branch)

    # push deploy.yml + config.json
    # deploy.yml blob
    expect_create_blob(repo)
    # config.json blob
    config_blob_expectation.()
    expect_get_commit(repo, branch)
    expect_create_tree(repo)
    expect_create_commit(repo)
    expect_update_ref(repo, branch)

    # write secret
    expect_get_public_key(repo)
    expect_create_repo_secret(repo, api_secret_name(%{project_id: project_id}))

    # initiate sync
    expect_create_installation_token(installation_id)
    expect_get_repo(repo, 200, expected_repo)
    expect_create_workflow_dispatch(repo, "openfn-pull.yml")
  end

  defp user_with_valid_github_oauth do
    # github_oauth_token is an encrypted map field: after an update the
    # in-memory struct still holds the raw terms we set (e.g. DateTime
    # structs), not the JSON-round-tripped string map that comes back
    # from a real DB read. Reload so callers get a token shaped the way
    # it actually looks when loaded from storage.
    insert(:user)
    |> set_valid_github_oauth_token!()
    |> Lightning.Repo.reload!()
  end
end
