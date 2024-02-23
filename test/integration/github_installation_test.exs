defmodule Lightning.Integration.GithubInstallationTest do
  use LightningWeb.ConnCase, async: false

  alias Lightning.VersionControl.GithubClient

  import Phoenix.LiveViewTest
  import Lightning.Factories

  @github_repo "OpenFn/github_integration_testing"
  @github_base_branch "main"
  @github_installation_id "41010069"
  @github_assets_dir Application.app_dir(:lightning, "priv/github")

  @moduletag :integration

  setup _ do
    Mox.stub_with(
      Lightning.GithubClient.Mock,
      Tesla.Adapter.Hackney
    )

    :ok
  end

  @tag :tmp_dir
  test "saving github repo connection commits the workflow files correctly", %{
    conn: conn,
    tmp_dir: tmp_dir
  } do
    {:ok, client} = GithubClient.build_client(@github_installation_id)
    test_branch_name = "test/#{Ecto.UUID.generate()}"

    on_exit(fn ->
      File.rm_rf(tmp_dir)
    end)

    user = insert(:user)
    project = insert(:project, project_users: [%{user: user, role: :admin}])

    repo_connection =
      insert(:project_repo_connection, %{
        project: project,
        user: user,
        github_installation_id: @github_installation_id,
        branch: nil,
        repo: nil
      })

    # create test branch

    {:ok, base_commit} =
      GithubClient.get_commit(
        client,
        @github_repo,
        "heads/#{@github_base_branch}"
      )

    {:ok, _branch_ref} =
      GithubClient.create_ref(client, @github_repo, %{
        sha: base_commit.body["sha"],
        ref: "refs/heads/#{test_branch_name}"
      })

    # download the files from github
    prev_dir = Path.join(tmp_dir, "prev")
    File.mkdir_p!(prev_dir)
    :ok = download_project(test_branch_name, tmp_dir, prev_dir)
    prev_files = find_files_in_directory(prev_dir)
    assert Enum.count(prev_files) >= 1

    # get rid of the owner
    downloaded_dir_name =
      [@github_repo, test_branch_name]
      |> Path.join()
      |> Path.split()
      |> tl()
      |> Enum.join("-")

    # pull.yml and deploy.yml don't exist yet
    for yml_file <- ["pull.yml", "deploy.yml"] do
      downloaded_yml_path =
        Path.join([
          prev_dir,
          downloaded_dir_name,
          ".github/workflows/#{yml_file}"
        ])

      refute File.exists?(downloaded_yml_path)
    end

    conn = log_in_user(conn, user)

    {:ok, view, _html} =
      live(
        conn,
        ~p"/projects/#{project.id}/settings#vcs"
      )

    assert view
           |> render_click("save_repo", %{
             branch: test_branch_name,
             repo: @github_repo
           }) =~
             "Repository:\n                            <a href=\"https://www.github.com/#{@github_repo}\" target=\"_blank\" class=\"hover:underline text-primary-600\">\n#{@github_repo}"

    updated_repo_connection = Lightning.Repo.reload(repo_connection)
    assert updated_repo_connection.branch == test_branch_name
    assert updated_repo_connection.repo == @github_repo

    # download the files from github
    curr_dir = Path.join(tmp_dir, "current")
    File.mkdir_p!(curr_dir)
    :ok = download_project(test_branch_name, tmp_dir, curr_dir)
    curr_files = find_files_in_directory(curr_dir)
    # the existing file + the 2 workflow files
    assert Enum.count(curr_files) >= 3

    # pull.yml and deploy.yml files are created
    for yml_file <- ["pull.yml", "deploy.yml"] do
      downloaded_yml_path =
        Path.join([
          curr_dir,
          downloaded_dir_name,
          ".github/workflows/#{yml_file}"
        ])

      assert File.exists?(downloaded_yml_path)

      assert File.read!(downloaded_yml_path) ==
               [@github_assets_dir, yml_file] |> Path.join() |> File.read!()
    end

    # all other previous files exist in the current dir
    for file <- prev_files do
      relative_path = Path.relative_to(file, prev_dir)
      curr_file_path = Path.join(curr_dir, relative_path)
      assert File.read!(file) == File.read!(curr_file_path)
    end

    # delete the branch.
    # fails to work if done in the `on_exit` callback because the stub
    # only works for the given process, but I guess the process is already dead at `on_exit`???
    GithubClient.delete_ref(
      client,
      @github_repo,
      "refs/heads/#{test_branch_name}"
    )
  end

  defp download_project(branch, working_dir, target_dir) do
    {:ok, %{body: zip_body}} =
      [Tesla.Middleware.FollowRedirects]
      |> Tesla.client()
      |> Tesla.get(
        "https://github.com/#{@github_repo}/archive/refs/heads/#{branch}.zip"
      )

    download_path = Path.join(working_dir, "#{Ecto.UUID.generate()}.zip")
    File.write!(download_path, zip_body)

    {:ok, _result} =
      :zip.unzip(to_charlist(download_path), [{:cwd, to_charlist(target_dir)}])

    :ok
  end

  defp find_files_in_directory(dir_path) do
    search_path = Path.join([dir_path, "**", "*"])

    search_path
    |> Path.wildcard(match_dot: true)
    |> Enum.reject(&File.dir?/1)
  end
end
