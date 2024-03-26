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
    changeset =
      ProjectRepoConnection.create_changeset(%ProjectRepoConnection{}, attrs)

    Repo.transact(fn ->
      with {:ok, repo_connection} <- Repo.insert(changeset),
           :ok <- configure_github_repo(repo_connection, user) do
        {:ok, repo_connection}
      end
    end)
  end

  @spec reconfigure_github_connection(ProjectRepoConnection.t(), User.t()) ::
          :ok | {:error, map()}
  def reconfigure_github_connection(repo_connection, user) do
    configure_github_repo(repo_connection, user)
  end

  @spec verify_github_connection(repo_connection :: ProjectRepoConnection.t()) ::
          :ok | {:error, GithubError.t() | map()}
  def verify_github_connection(repo_connection) do
    with {:ok, client} <-
           GithubClient.build_installation_client(
             repo_connection.github_installation_id
           ),
         :ok <-
           verify_file_exists(client, repo_connection, pull_yml_target_path()),
         :ok <-
           verify_file_exists(client, repo_connection, deploy_yml_target_path()),
         :ok <- verify_file_exists(client, repo_connection, "project.yml"),
         :ok <- verify_file_exists(client, repo_connection, ".state.json"),
         :ok <-
           verify_repo_secret_exists(
             client,
             repo_connection,
             deploy_secret_name()
           ) do
      :ok
    end
  end

  @doc """
  Deletes a github connection
  """
  def remove_github_connection(repo_connection, user) do
    repo_connection
    |> Repo.delete()
    |> tap(fn
      {:ok, repo_connection} ->
        maybe_delete_workflow_files(
          repo_connection,
          user
        )

      _other ->
        :ok
    end)
  end

  def get_repo_connection_for_project(project_id) do
    Repo.get_by(ProjectRepoConnection, project_id: project_id)
  end

  @spec inititiate_sync(
          repo_connection :: ProjectRepoConnection.t(),
          user_email :: String.t()
        ) :: :ok | {:error, map()}
  def inititiate_sync(repo_connection, user_email) do
    with {:ok, client} <-
           GithubClient.build_installation_client(
             repo_connection.github_installation_id
           ),
         {:ok, %Tesla.Env{status: 204}} <-
           GithubClient.create_repo_dispatch_event(
             client,
             repo_connection.repo,
             %{
               event_type: "sync_project",
               client_payload: %{
                 message: "#{user_email} initiated a sync from Lightning"
               }
             }
           ) do
      :ok
    else
      {:ok, %Tesla.Env{} = result} ->
        {:error, result}

      other ->
        other
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
          repo_connection :: ProjectRepoConnection.t()
        ) :: {:ok, Tesla.Env.t()} | {:error, Tesla.Env.t() | GithubError.t()}
  defp push_workflow_files(client, repo_connection) do
    with {:ok, %{status: 201, body: pull_blob}} <-
           GithubClient.create_blob(client, repo_connection.repo, %{
             content: pull_yml()
           }),
         {:ok, %{status: 201, body: deploy_blob}} <-
           GithubClient.create_blob(client, repo_connection.repo, %{
             content: deploy_yml()
           }),
         {:ok, %{status: 200, body: base_commit}} <-
           GithubClient.get_commit(
             client,
             repo_connection.repo,
             "heads/#{repo_connection.branch}"
           ),
         {:ok, %{status: 201, body: created_tree}} <-
           GithubClient.create_tree(client, repo_connection.repo, %{
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
           GithubClient.create_commit(client, repo_connection.repo, %{
             message: "configure OpenFn",
             tree: created_tree["sha"],
             parents: [base_commit["sha"]]
           }),
         {:ok, %{status: 200, body: updated_ref}} <-
           GithubClient.update_ref(
             client,
             repo_connection.repo,
             "heads/#{repo_connection.branch}",
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

  defp deploy_secret_name do
    "OPENFN_API_KEY"
  end

  defp maybe_delete_workflow_files(repo_connection, user) do
    with {:ok, access_token} <- fetch_user_access_token(user),
         {:ok, client} <- GithubClient.build_bearer_client(access_token) do
      pull_path = pull_yml_target_path()
      deploy_path = deploy_yml_target_path()
      maybe_delete_file(client, repo_connection, pull_path)
      maybe_delete_file(client, repo_connection, deploy_path)
    end
  end

  defp maybe_delete_file(client, repo_connection, file_path) do
    with {:ok, %{status: 200, body: %{"sha" => sha}}} <-
           GithubClient.get_repo_content(
             client,
             repo_connection.repo,
             file_path,
             "heads/#{repo_connection.branch}"
           ) do
      GithubClient.delete_repo_content(
        client,
        repo_connection.repo,
        file_path,
        %{
          sha: sha,
          message: "disconnect OpenFn",
          branch: repo_connection.branch
        }
      )
    end
  end

  defp configure_deploy_secret(client, repo_connection) do
    with {:ok, %{status: 200, body: resp_body}} <-
           GithubClient.get_repo_public_key(client, repo_connection.repo) do
      public_key = Base.decode64!(resp_body["key"])

      encrypted_secret =
        :enacl.box_seal(repo_connection.access_token, public_key)

      case GithubClient.create_repo_secret(
             client,
             repo_connection.repo,
             deploy_secret_name(),
             %{
               encrypted_value: Base.encode64(encrypted_secret),
               key_id: resp_body["key_id"]
             }
           ) do
        {:ok, %{status: status} = resp} when status in [201, 204] ->
          {:ok, resp}

        {:ok, %Tesla.Env{} = result} ->
          {:error, result}

        other ->
          other
      end
    else
      {:ok, %Tesla.Env{} = result} ->
        {:error, result}

      other ->
        other
    end
  end

  @spec configure_github_repo(ProjectRepoConnection.t(), User.t()) ::
          :ok | {:error, map()}
  defp configure_github_repo(repo_connection, user) do
    with {:ok, user_token} <- fetch_user_access_token(user),
         {:ok, tesla_client} <- GithubClient.build_bearer_client(user_token),
         {:ok, _} <- push_workflow_files(tesla_client, repo_connection),
         {:ok, _} <- configure_deploy_secret(tesla_client, repo_connection) do
      inititiate_sync(repo_connection, user.email)
    end
  end

  defp verify_file_exists(client, repo_connection, file_path) do
    case GithubClient.get_repo_content(
           client,
           repo_connection.repo,
           file_path,
           "heads/#{repo_connection.branch}"
         ) do
      {:ok, %{status: 200}} ->
        :ok

      _other ->
        {:error,
         GithubError.file_not_found(
           "#{file_path} does not exist in the given branch"
         )}
    end
  end

  defp verify_repo_secret_exists(client, repo_connection, secret_name) do
    case GithubClient.get_repo_secret(client, repo_connection.repo, secret_name) do
      {:ok, %{status: 200}} ->
        :ok

      _other ->
        {:error,
         GithubError.repo_secret_not_found(
           "#{secret_name} has not been set in the repo"
         )}
    end
  end
end
