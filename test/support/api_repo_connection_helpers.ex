defmodule LightningWeb.ApiRepoConnectionHelpers do
  @moduledoc """
  GitHub's side of the repo connection routes, as `Lightning.Tesla.Mock`
  expectations, and a person who has connected their GitHub account.
  """
  use LightningWeb, :verified_routes

  import Lightning.Factories
  import Lightning.GithubHelpers
  import LightningWeb.ApiSandboxesHelpers, only: [send_json: 4]

  @repo "someaccount/somerepo"
  @installation_id "1234"

  def repo, do: @repo
  def installation_id, do: @installation_id

  def put_repo_connection(conn, project_id, body),
    do:
      send_json(
        conn,
        :put,
        ~p"/api/projects/#{project_id}/repo_connection",
        body
      )

  def sync_repo_connection(conn, project_id, body \\ %{}),
    do:
      send_json(
        conn,
        :post,
        ~p"/api/projects/#{project_id}/repo_connection/syncs",
        body
      )

  @doc "A user who has connected their GitHub account, as loaded from storage."
  def github_user(attrs \\ []) do
    :user
    |> insert(attrs)
    |> set_valid_github_oauth_token!()
    |> Lightning.Repo.reload!()
  end

  def api_secret_name(project_id),
    do: "OPENFN_#{String.replace(project_id, "-", "_")}_API_KEY"

  @doc """
  GitHub answering everything Lightning writes when it connects or reconnects
  `project_id` to `branch` with the caller's token: the pull workflow on the
  default branch, the repo secret, and the deploy workflow and config on the
  branch, then, for `pull`, the sync it starts with the installation's token.
  """
  def expect_connecting(project_id, branch, opts \\ []) do
    default_branch = "main"

    expect_get_repo(@repo)
    expect_create_blob(@repo)
    expect_get_commit(@repo, default_branch)
    expect_create_tree(@repo)
    expect_create_commit(@repo)
    expect_update_ref(@repo, default_branch)

    expect_get_public_key(@repo)
    expect_create_repo_secret(@repo, api_secret_name(project_id))

    # The deploy workflow, then the config Lightning writes unless the
    # connection names an existing one.
    expect_create_blob(@repo)
    if Keyword.get(opts, :config_blob, true), do: expect_create_blob(@repo)
    expect_get_commit(@repo, branch)
    expect_create_tree(@repo)
    expect_create_commit(@repo)
    expect_update_ref(@repo, branch)

    if Keyword.get(opts, :sync, true), do: expect_sync()
  end

  @doc """
  GitHub answering Lightning's clean-up of what a connection wrote:
  the deploy workflow and config on its branch, and the repo secret unless
  `keep_secret`.
  """
  def expect_cleaning_up(project_id, opts \\ []) do
    for path <- [
          ".github/workflows/openfn-#{project_id}-deploy.yml",
          "openfn-#{project_id}-config.json"
        ] do
      expect_get_repo_content(@repo, path)
      expect_delete_repo_content(@repo, path)
    end

    if !Keyword.get(opts, :keep_secret, false),
      do: expect_delete_repo_secret(@repo, api_secret_name(project_id))
  end

  @doc "GitHub accepting the pull workflow's dispatch, with the installation's token."
  def expect_sync(installation_id \\ @installation_id) do
    expect_create_installation_token(installation_id)
    expect_get_repo(@repo)
    expect_create_workflow_dispatch(@repo, "openfn-pull.yml")
  end
end
