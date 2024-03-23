defmodule Lightning.VersionControl do
  @moduledoc """
  Boundary module for handling Version control activities for project, jobs
  workflows etc
  Use this module to create, modify and delete connections as well
  as running any associated sync jobs
  """

  import Ecto.Query, warn: false

  alias Lightning.Accounts.User
  alias Lightning.Repo
  alias Lightning.VersionControl.Events
  alias Lightning.VersionControl.GithubClient
  alias Lightning.VersionControl.GithubError
  alias Lightning.VersionControl.ProjectRepoConnection

  defdelegate subscribe(user), to: Events

  @doc """
  Creates a connection between a project and a github repo
  """
  def create_github_connection(attrs, user) do
    changeset = ProjectRepoConnection.changeset(%ProjectRepoConnection{}, attrs)

    Repo.transact(fn ->
      with {:ok, repo_connection} <- Repo.insert(changeset),
           {:ok, user_token} <- fetch_user_access_token(user),
           {:ok, tesla_client} <- GithubClient.build_bearer_client(user_token),
           {:ok, _} <-
             push_workflow_files(
               tesla_client,
               repo_connection.repo,
               repo_connection.branch
             ) do
        {:ok, repo_connection}
      end
    end)
  end

  @doc """
  Deletes a github connection used when re installing
  """
  def remove_github_connection(repo_connection, user) do
    repo_connection
    |> Repo.delete()
    |> tap(fn
      {:ok, repo_connection} ->
        maybe_delete_workflow_files(
          user,
          repo_connection.repo,
          repo_connection.branch
        )

      _other ->
        :ok
    end)
  end

  def get_repo_connection(project_id) do
    Repo.one(
      from(prc in ProjectRepoConnection, where: prc.project_id == ^project_id)
    )
  end

  def initiate_sync(project_id, user_name) do
    with %ProjectRepoConnection{} = repo_connection <-
           Repo.get_by(ProjectRepoConnection, project_id: project_id) do
      GithubClient.fire_repository_dispatch(
        repo_connection.github_installation_id,
        repo_connection.repo,
        user_name
      )
    end
  end

  def fetch_user_installations(user) do
    with {:ok, access_token} <- fetch_user_access_token(user),
         {:ok, client} <- GithubClient.build_bearer_client(access_token) do
      case GithubClient.get_installations(client) do
        {:ok, %{status: 200, body: body}} ->
          {:ok, body}

        {:ok, %{body: body}} ->
          {:error, body}
      end
    end
  end

  def fetch_installation_repos(installation_id) do
    with {:ok, client} <- GithubClient.build_installation_client(installation_id) do
      case GithubClient.get_installation_repos(client) do
        {:ok, %{status: 200, body: body}} ->
          {:ok, body}

        {:ok, %{body: body}} ->
          {:error, body}
      end
    end
  end

  def fetch_repo_branches(installation_id, repo_name) do
    with {:ok, client} <- GithubClient.build_installation_client(installation_id) do
      case GithubClient.get_repo_branches(client, repo_name) do
        {:ok, %{status: 200, body: body}} ->
          {:ok, body}

        {:ok, %{body: body}} ->
          {:error, body}
      end
    end
  end

  @doc """
  Fetches the oauth access token using the code received from the callback url
  For more info: https://docs.github.com/en/apps/creating-github-apps/authenticating-with-a-github-app/generating-a-user-access-token-for-a-github-app
  """
  @spec exchange_code_for_oauth_token(code :: String.t()) ::
          {:ok, map()} | {:error, map()}
  def exchange_code_for_oauth_token(code) do
    app_config = Application.fetch_env!(:lightning, :github_app)

    query_params = [
      client_id: app_config[:client_id],
      client_secret: app_config[:client_secret],
      code: code
    ]

    {:ok, tesla_client} = GithubClient.build_oauth_client()

    case Tesla.post(tesla_client, "/access_token", %{}, query: query_params) do
      {:ok, %{body: %{"access_token" => _} = body}} ->
        {:ok, body}

      {:ok, %{body: body}} ->
        {:error, body}

      other ->
        other
    end
  end

  @doc """
  Fetches a new access token using the given refresh token
  For more info: https://docs.github.com/en/apps/creating-github-apps/authenticating-with-a-github-app/refreshing-user-access-tokens
  """
  @spec refresh_oauth_token(refresh_token :: String.t()) ::
          {:ok, map()} | {:error, map()}
  def refresh_oauth_token(refresh_token) do
    app_config = Application.fetch_env!(:lightning, :github_app)

    query_params = [
      client_id: app_config[:client_id],
      client_secret: app_config[:client_secret],
      grant_type: "refresh_token",
      refresh_token: refresh_token
    ]

    {:ok, client} = GithubClient.build_oauth_client()

    case Tesla.post(client, "/access_token", %{}, query: query_params) do
      {:ok, %{body: %{"access_token" => _} = body}} ->
        {:ok, body}

      {:ok, %{body: body}} ->
        {:error, body}

      other ->
        other
    end
  end

  @doc """
  Checks if the given token has expired.
  Github supports access tokens that expire and those that don't.
  If the `access token` expires, then a `refresh token` is also availed.
  This function simply checks if the token has a `refresh_token`, if yes, it proceeds to check the expiry date
  """
  @spec oauth_token_valid?(token :: map()) :: boolean()
  def oauth_token_valid?(token) do
    case token do
      %{"refresh_token_expires_at" => expiry} ->
        {:ok, expiry, _offset} = DateTime.from_iso8601(expiry)
        now = DateTime.utc_now()
        DateTime.after?(expiry, now)

      %{"access_token" => _access_token} ->
        true

      _other ->
        false
    end
  end

  @doc """
  Fecthes the access token for the given `User`.
  If the access token has expired, it `refreshes` the token and updates the `User` column accordingly
  """
  @spec fetch_user_access_token(User.t()) ::
          {:ok, String.t()} | {:error, map()}
  # token that expires
  def fetch_user_access_token(
        %User{
          github_oauth_token: %{"refresh_token_expires_at" => _expiry}
        } = user
      ) do
    maybe_refresh_access_token(user)
  end

  # token that doesn't expire
  def fetch_user_access_token(%User{
        github_oauth_token: %{"access_token" => access_token}
      }) do
    {:ok, access_token}
  end

  def fetch_user_access_token(_user) do
    {:error,
     GithubError.invalid_oauth_token("user has not configured an oauth token")}
  end

  defp maybe_refresh_access_token(%User{github_oauth_token: token} = user) do
    {:ok, access_token_expiry, _offset} =
      DateTime.from_iso8601(token["expires_at"])

    now = DateTime.utc_now()

    if DateTime.after?(access_token_expiry, now) do
      {:ok, token["access_token"]}
    else
      with {:ok, refreshed_token} <- refresh_oauth_token(token["refresh_token"]),
           {:ok, _user} <- save_oauth_token(user, refreshed_token, notify: false) do
        {:ok, refreshed_token["access_token"]}
      end
    end
  end

  @doc """
  Deletes the authorization for the github app and updates the user details accordingly
  """
  @spec delete_github_ouath_grant(User.t()) :: {:ok, User.t()} | {:error, any()}
  def delete_github_ouath_grant(%User{} = user) do
    app_config = Application.fetch_env!(:lightning, :github_app)
    client_id = Keyword.fetch!(app_config, :client_id)
    client_secret = Keyword.fetch!(app_config, :client_secret)

    with {:ok, access_token} <- fetch_user_access_token(user),
         {:ok, client} <-
           GithubClient.build_basic_auth_client(
             client_id,
             client_secret
           ),
         {:ok, %{status: 204}} <-
           GithubClient.delete_app_grant(
             client,
             client_id,
             access_token
           ) do
      user |> Ecto.Changeset.change(%{github_oauth_token: nil}) |> Repo.update()
    end
  end

  @spec save_oauth_token(User.t(), map(), notify: boolean()) ::
          {:ok, User.t()} | {:error, Ecto.Changeset.t()}
  def save_oauth_token(%User{} = user, token, opts \\ [notify: true]) do
    token =
      token
      |> maybe_add_access_token_expiry_date()
      |> maybe_add_refresh_token_expiry_date()

    user
    |> User.github_token_changeset(%{github_oauth_token: token})
    |> Repo.update()
    |> tap(fn
      {:ok, user} ->
        if opts[:notify] do
          Events.oauth_token_added(user)
        end

      _other ->
        :ok
    end)
  end

  defp maybe_add_access_token_expiry_date(token) do
    if expires_in = token["expires_in"] do
      Map.merge(token, %{
        "expires_at" => DateTime.utc_now() |> DateTime.add(expires_in)
      })
    else
      token
    end
  end

  defp maybe_add_refresh_token_expiry_date(token) do
    if expires_in = token["refresh_token_expires_in"] do
      Map.merge(token, %{
        "refresh_token_expires_at" =>
          DateTime.utc_now() |> DateTime.add(expires_in)
      })
    else
      token
    end
  end

  def github_enabled? do
    Application.get_env(:lightning, :github_app, [])
    |> then(fn config ->
      Keyword.get(config, :cert) && Keyword.get(config, :app_id) &&
        Keyword.get(config, :client_id) && Keyword.get(config, :client_secret)
    end)
  end

  @spec push_workflow_files(
          client :: Tesla.Client.t(),
          repo :: String.t(),
          branch :: String.t()
        ) :: {:ok, Tesla.Env.t()} | {:error, Tesla.Env.t() | GithubError.t()}
  defp push_workflow_files(client, repo, branch) do
    with {:ok, %{status: 201, body: pull_blob}} <-
           GithubClient.create_blob(client, repo, %{
             content: pull_yml()
           }),
         {:ok, %{status: 201, body: deploy_blob}} <-
           GithubClient.create_blob(client, repo, %{
             content: deploy_yml()
           }),
         {:ok, %{status: 200, body: base_commit}} <-
           GithubClient.get_commit(
             client,
             repo,
             "heads/#{branch}"
           ),
         {:ok, %{status: 201, body: created_tree}} <-
           GithubClient.create_tree(client, repo, %{
             base_tree: base_commit["commit"]["tree"]["sha"],
             tree: [
               %{
                 path: pull_yml_target_path(),
                 mode: "100644",
                 type: "blob",
                 sha: pull_blob["sha"]
               },
               %{
                 path: deploy_yml_target_path(),
                 mode: "100644",
                 type: "blob",
                 sha: deploy_blob["sha"]
               }
             ]
           }),
         {:ok, %{status: 201, body: created_commit}} <-
           GithubClient.create_commit(client, repo, %{
             message: "configure OpenFn",
             tree: created_tree["sha"],
             parents: [base_commit["sha"]]
           }),
         {:ok, %{status: 200, body: updated_ref}} <-
           GithubClient.update_ref(
             client,
             repo,
             "heads/#{branch}",
             %{sha: created_commit["sha"]}
           ) do
      {:ok, updated_ref}
    else
      {:ok, %Tesla.Env{} = result} ->
        {:error, result}

      other ->
        other
    end
  end

  defp pull_yml do
    :code.priv_dir(:lightning)
    |> Path.join("github/pull.yml")
    |> File.read!()
  end

  defp deploy_yml do
    :code.priv_dir(:lightning)
    |> Path.join("github/deploy.yml")
    |> File.read!()
  end

  defp pull_yml_target_path do
    ".github/workflows/pull.yml"
  end

  defp deploy_yml_target_path do
    ".github/workflows/deploy.yml"
  end

  defp maybe_delete_workflow_files(user, repo, branch) do
    with {:ok, access_token} <- fetch_user_access_token(user),
         {:ok, client} <- GithubClient.build_bearer_client(access_token) do
      pull_path = pull_yml_target_path()
      deploy_path = deploy_yml_target_path()
      maybe_delete_file(client, repo, branch, pull_path)
      maybe_delete_file(client, repo, branch, deploy_path)
    end
  end

  defp maybe_delete_file(client, repo, branch, file_path) do
    with {:ok, %{status: 200, body: %{"sha" => sha}}} <-
           GithubClient.get_repo_content(
             client,
             repo,
             file_path,
             "heads/#{branch}"
           ) do
      GithubClient.delete_repo_content(client, repo, file_path, %{
        sha: sha,
        message: "disconnect OpenFn",
        branch: branch
      })
    end
  end
end
