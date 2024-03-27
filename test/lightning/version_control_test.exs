defmodule Lightning.VersionControlTest do
  use Lightning.DataCase, async: true
  alias Lightning.VersionControl
  alias Lightning.VersionControl.ProjectRepoConnection
  alias Lightning.Repo

  import Lightning.Factories

  @public_key """
  -----BEGIN PUBLIC KEY-----
  MIIBITANBgkqhkiG9w0BAQEFAAOCAQ4AMIIBCQKCAQB1ZtDWukVcNcnMLXUsi8Mw
  6WK5pri2sXuNZpT8lMf2fXcEmsJdvEhP3DASDykLyusJp9fV17BzM8JmzC9zNMIc
  OdLhwsl8rKoVrwYjFXXRvPn+5QzpwT/JprymE54lbFJ/lMefkfkJcaSl5khyHNpl
  rGH5g7+zGiMfs+kXItjhW41xEsy552kff3Wq/33R2sdizIDDJjEC/6J942jLpMJe
  HgYaZXZRKsc9b6CSjZS/nVh0OA/bE4deNrSDesyytcMmN3/+l9XYbQqJOgVs/sWl
  TNPEVQabXsPxzIwVGcH+iDRhV31nqe6YoQ/gvNTRnESnC1KRrTB7eCwZP0kHLshX
  AgMBAAE=
  -----END PUBLIC KEY-----
  """

  describe "create_github_connection/2" do
    test "user with valid oauth token creates connection successfully" do
      Mox.verify_on_exit!()

      project = insert(:project)
      user = user_with_valid_github_ouath()

      assert Repo.aggregate(ProjectRepoConnection, :count) == 0

      params = %{
        "project_id" => project.id,
        "repo" => "some/repo",
        "branch" => "somebranch",
        "github_installation_id" => "1234"
      }

      github_connection_expectations(
        params["github_installation_id"],
        params["repo"],
        params["branch"]
      )

      assert {:ok, repo_connection} =
               VersionControl.create_github_connection(
                 params,
                 user
               )

      assert String.starts_with?(repo_connection.access_token, "prc_")

      assert Repo.aggregate(ProjectRepoConnection, :count) == 1

      assert repo_connection.project_id == project.id
      assert repo_connection.branch == params["branch"]
      assert repo_connection.repo == params["repo"]

      assert repo_connection.github_installation_id ==
               params["github_installation_id"]
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
      user = user_with_valid_github_ouath()

      repo_connection =
        insert(:project_repo_connection,
          project: project,
          repo: "someaccount/somerepo",
          branch: "somebranch",
          github_installation_id: "1234",
          access_token: "someaccesstoken"
        )

      repo_name = repo_connection.repo

      assert is_map(user.github_oauth_token)

      Mox.expect(Lightning.Tesla.Mock, :call, 4, fn env, _opts ->
        case env do
          # check if pull yml exists for deletion
          %{
            method: :get,
            url:
              "https://api.github.com/repos/" <>
                  ^repo_name <> "/contents/.github/workflows/pull.yml"
          } ->
            {:ok, %Tesla.Env{status: 200, body: %{"sha" => "somesha"}}}

          # delete pull yml
          %{
            method: :delete,
            url:
              "https://api.github.com/repos/" <>
                  ^repo_name <> "/contents/.github/workflows/pull.yml"
          } ->
            {:ok, %Tesla.Env{status: 200, body: %{"sha" => "somesha"}}}

          # check if deploy yml exists for deletion
          %{
            method: :get,
            url:
              "https://api.github.com/repos/" <>
                  ^repo_name <> "/contents/.github/workflows/deploy.yml"
          } ->
            {:ok, %Tesla.Env{status: 200, body: %{"sha" => "somesha"}}}

          # delete deploy yml.
          %{
            method: :delete,
            url:
              "https://api.github.com/repos/" <>
                  ^repo_name <> "/contents/.github/workflows/deploy.yml"
          } ->
            {:ok, %Tesla.Env{status: 400, body: %{"something" => "happened"}}}
        end
      end)

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

  defp user_with_valid_github_ouath do
    active_token = %{
      "access_token" => "access-token",
      "refresh_token" => "refresh-token",
      "expires_at" => DateTime.utc_now() |> DateTime.add(500),
      "refresh_token_expires_at" => DateTime.utc_now() |> DateTime.add(500)
    }

    insert(:user, github_oauth_token: active_token) |> Lightning.Repo.reload()
  end

  defp github_connection_expectations(
         installation_id,
         expected_repo_name,
         expected_branch_name
       ) do
    installation_id = to_string(installation_id)

    Mox.expect(Lightning.Tesla.Mock, :call, 10, fn env, _opts ->
      case env.url do
        # create blob. called twice (for push.yml and deploy.yml)
        "https://api.github.com/repos/" <> ^expected_repo_name <> "/git/blobs" ->
          {:ok,
           %Tesla.Env{
             status: 201,
             body: %{"sha" => "3a0f86fb8db8eea7ccbb9a95f325ddbedfb25e15"}
           }}

        # get commit on selected branch
        "https://api.github.com/repos/" <>
            ^expected_repo_name <>
            "/commits/heads/" <>
            ^expected_branch_name ->
          {:ok,
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
           }}

        # create commit
        "https://api.github.com/repos/" <> ^expected_repo_name <> "/git/commits" ->
          {:ok,
           %Tesla.Env{
             status: 201,
             body: %{"sha" => "7638417db6d59f3c431d3e1f261cc637155684cd"}
           }}

        # create tree
        "https://api.github.com/repos/" <> ^expected_repo_name <> "/git/trees" ->
          {:ok,
           %Tesla.Env{
             status: 201,
             body: %{"sha" => "cd8274d15fa3ae2ab983129fb037999f264ba9a7"}
           }}

        # update a reference on the selected branch
        "https://api.github.com/repos/" <>
            ^expected_repo_name <>
            "/git/refs/heads/" <>
            ^expected_branch_name ->
          {:ok,
           %Tesla.Env{
             status: 200,
             body: %{"ref" => "refs/heads/master"}
           }}

        # get repo public key
        "https://api.github.com/repos/" <>
            ^expected_repo_name <> "/actions/secrets/public-key" ->
          {:ok,
           %Tesla.Env{
             status: 200,
             body: %{
               "key" => Base.encode64(@public_key),
               "key_id" => "012345678912345678"
             }
           }}

        # create the OPENFN_API_KEY repo secret
        "https://api.github.com/repos/" <>
            ^expected_repo_name <> "/actions/secrets/OPENFN_API_KEY" ->
          {:ok, %Tesla.Env{status: 201, body: ""}}

        # token for sync
        "https://api.github.com/app/installations/" <>
            ^installation_id <> "/access_tokens" ->
          {:ok,
           %Tesla.Env{
             status: 201,
             body: %{"token" => "some-token"}
           }}

        # initialize sync
        "https://api.github.com/repos/" <>
            ^expected_repo_name <> "/dispatches" ->
          {:ok, %Tesla.Env{status: 204, body: ""}}
      end
    end)
  end
end
