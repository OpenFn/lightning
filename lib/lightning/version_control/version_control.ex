defmodule Lightning.VersionControl do
  @moduledoc """
  Boundary module for handling Version control activities for project, jobs
  workflows etc
  Use this module to create, modify and delete connections as well
  as running any associated sync jobs
  """

  import Ecto.Query, warn: false

  alias Ecto.Multi
  alias Lightning.Accounts.User
  alias Lightning.Extensions.UsageLimiting
  alias Lightning.Repo
  alias Lightning.VersionControl.Audit
  alias Lightning.VersionControl.Events
  alias Lightning.VersionControl.GithubClient
  alias Lightning.VersionControl.GithubError
  alias Lightning.VersionControl.ProjectRepoConnection
  alias Lightning.VersionControl.VersionControlUsageLimiter
  alias Lightning.Workflows.Workflow

  require Logger

  defdelegate subscribe(user), to: Events

  @doc """
  Creates a connection between a project and a github repo
  """
  @spec create_github_connection(map(), User.t()) ::
          {:ok, ProjectRepoConnection.t()}
          | {:error, Ecto.Changeset.t() | UsageLimiting.message()}
  def create_github_connection(attrs, user) do
    changeset =
      ProjectRepoConnection.create_changeset(%ProjectRepoConnection{}, attrs)

    Repo.transact(fn ->
      with {:ok, repo_connection} <- Repo.insert(changeset),
           {:ok, _audit} <-
             repo_connection
             |> Audit.repo_connection(:created, user)
             |> Repo.insert(),
           :ok <-
             VersionControlUsageLimiter.limit_github_sync(
               repo_connection.project_id
             ),
           :ok <- configure_github_repo(repo_connection, user) do
        {:ok, repo_connection}
      end
    end)
  end

  @spec reconfigure_github_connection(ProjectRepoConnection.t(), map(), User.t()) ::
          :ok | {:error, UsageLimiting.message() | map()}
  def reconfigure_github_connection(repo_connection, params, user) do
    changeset =
      ProjectRepoConnection.reconfigure_changeset(repo_connection, params)

    with :ok <-
           VersionControlUsageLimiter.limit_github_sync(
             repo_connection.project_id
           ),
         {:ok, updated_repo_connection} <-
           Ecto.Changeset.apply_action(changeset, :update) do
      configure_github_repo(updated_repo_connection, user)
    end
  end

  @spec verify_github_connection(repo_connection :: ProjectRepoConnection.t()) ::
          :ok | {:error, GithubError.t() | map()}
  def verify_github_connection(repo_connection) do
    with {:ok, client} <-
           GithubClient.build_installation_client(
             repo_connection.github_installation_id
           ),
         {:ok, %{status: 200, body: %{"default_branch" => default_branch}}} <-
           GithubClient.get_repo(client, repo_connection.repo),
         :ok <-
           verify_file_exists(
             client,
             repo_connection.repo,
             default_branch,
             pull_yml_target_path()
           ),
         :ok <-
           verify_file_exists(
             client,
             repo_connection.repo,
             repo_connection.branch,
             deploy_yml_target_path(repo_connection)
           ),
         :ok <-
           verify_file_exists(
             client,
             repo_connection.repo,
             repo_connection.branch,
             config_target_path(repo_connection)
           ) do
      verify_repo_secret_exists(
        client,
        repo_connection,
        api_secret_name(repo_connection)
      )
    end
  end

  @doc """
  Deletes a github connection
  """
  def remove_github_connection(repo_connection, user) do
    Multi.new()
    |> Multi.delete(:delete_repo_connection, repo_connection)
    |> Multi.insert(
      :audit,
      Audit.repo_connection(repo_connection, :removed, user)
    )
    |> Repo.transaction()
    |> tap(fn
      {:ok, %{delete_repo_connection: repo_connection}} ->
        undo_repo_actions(
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

  def get_repo_connection_for_token(token) do
    Repo.get_by(ProjectRepoConnection, access_token: token)
  end

  @spec initiate_sync(
          repo_connection :: ProjectRepoConnection.t(),
          commit_message :: String.t()
        ) :: :ok | {:error, UsageLimiting.message() | map()}
  def initiate_sync(repo_connection, commit_message) do
    with :ok <-
           VersionControlUsageLimiter.limit_github_sync(
             repo_connection.project_id
           ),
         snapshots <-
           list_snapshots_for_project(repo_connection),
         {:ok, client} <-
           GithubClient.build_installation_client(
             repo_connection.github_installation_id
           ),
         {:ok, %{status: 200, body: %{"default_branch" => default_branch}}} <-
           GithubClient.get_repo(client, repo_connection.repo),
         {:ok, %Tesla.Env{status: 204}} <-
           GithubClient.create_workflow_dispatch_event(
             client,
             repo_connection.repo,
             pull_yml_target_path() |> Path.basename(),
             %{
               ref: default_branch,
               inputs:
                 %{
                   projectId: repo_connection.project_id,
                   apiSecretName: api_secret_name(repo_connection),
                   pathToConfig: config_target_path(repo_connection),
                   branch: repo_connection.branch,
                   commitMessage: commit_message
                 }
                 |> maybe_add_snapshots(snapshots)
             }
           ) do
      :ok
    end
  end

  defp list_snapshots_for_project(%{project_id: project_id}) do
    current_query =
      from w in Workflow,
        join: s in assoc(w, :snapshots),
        on: s.lock_version == w.lock_version,
        where: w.project_id == ^project_id and is_nil(w.deleted_at),
        select: s.id

    Repo.all(current_query) |> Enum.reverse()
  end

  defp maybe_add_snapshots(inputs, snapshot_ids) do
    if Enum.empty?(snapshot_ids) do
      inputs
    else
      Map.put(inputs, :snapshots, Enum.join(snapshot_ids, " "))
    end
  end

  def fetch_user_installations(user) do
    with {:ok, access_token} <- fetch_user_access_token(user),
         {:ok, client} <- GithubClient.build_bearer_client(access_token) do
      case GithubClient.get_installations(client) do
        {:ok, %{body: body}} ->
          {:ok, body}

        {:error, %{body: body}} ->
          {:error, body}
      end
    end
  end

  def fetch_installation_repos(installation_id) do
    with {:ok, client} <- GithubClient.build_installation_client(installation_id) do
      case GithubClient.get_installation_repos(client, page: 1, per_page: 100) do
        {:ok, %{body: body}} ->
          {:ok, maybe_fetch_remaining_repos(client, body)}

        {:error, %{body: body}} ->
          {:error, body}
      end
    end
  end

  defp maybe_fetch_remaining_repos(
         client,
         %{"total_count" => total_count} = initial_result
       )
       when total_count > 100 do
    2..ceil(total_count / 100)
    |> Task.async_stream(
      fn page ->
        GithubClient.get_installation_repos(client, page: page, per_page: 100)
      end,
      timeout: :infinity,
      max_concurrency: 5
    )
    |> Enum.reduce(initial_result, fn
      {:ok, {:ok, %{body: body}}}, acc ->
        %{acc | "repositories" => body["repositories"] ++ acc["repositories"]}

      {:ok, {:error, %{body: body}}}, acc ->
        Logger.error(
          "Failed to fetch a subsequent github repositories page: #{inspect(body)}"
        )

        acc
    end)
  end

  defp maybe_fetch_remaining_repos(_client, initial_result), do: initial_result

  def fetch_repo_branches(installation_id, repo_name) do
    with {:ok, client} <- GithubClient.build_installation_client(installation_id) do
      case GithubClient.get_repo_branches(client, repo_name) do
        {:ok, %{body: body}} ->
          {:ok, body}

        {:error, %{body: body}} ->
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
  GitHub supports access tokens that expire and those that don't.
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
          github_oauth_token: %{"refresh_token_expires_at" => expiry}
        } = user
      ) do
    {:ok, token_expiry, _offset} =
      DateTime.from_iso8601(expiry)

    now = DateTime.utc_now()

    if DateTime.after?(token_expiry, now) do
      maybe_refresh_access_token(user)
    else
      {:error, GithubError.invalid_oauth_token("user refresh token has expired")}
    end
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
  @spec delete_github_oauth_grant(User.t()) :: {:ok, User.t()} | {:error, map()}
  def delete_github_oauth_grant(%User{} = user) do
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
      remove_oauth_token(user)
    else
      {:error, error} ->
        Logger.error("Error deleting github app grant: #{inspect(error)}")
        remove_oauth_token(user)
    end
  end

  defp remove_oauth_token(user) do
    user |> User.remove_github_token_changeset() |> Repo.update()
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

  @spec push_files_to_selected_branch(
          client :: Tesla.Client.t(),
          repo_connection :: ProjectRepoConnection.t()
        ) :: {:ok, Tesla.Env.t()} | {:error, Tesla.Env.t() | GithubError.t()}
  defp push_files_to_selected_branch(client, repo_connection) do
    with {:ok, %{status: 201, body: deploy_blob}} <-
           GithubClient.create_blob(client, repo_connection.repo, %{
             content: deploy_yml(repo_connection)
           }),
         {:ok, config_blob_or_nil} <-
           maybe_create_config_blob(client, repo_connection),
         {:ok, %{status: 200, body: base_commit}} <-
           GithubClient.get_commit(
             client,
             repo_connection.repo,
             "heads/#{repo_connection.branch}"
           ),
         {:ok, %{status: 201, body: created_tree}} <-
           GithubClient.create_tree(client, repo_connection.repo, %{
             base_tree: base_commit["commit"]["tree"]["sha"],
             tree:
               [
                 %{
                   path: deploy_yml_target_path(repo_connection),
                   mode: "100644",
                   type: "blob",
                   sha: deploy_blob["sha"]
                 }
               ] ++
                 maybe_include_config_tree(repo_connection, config_blob_or_nil)
           }),
         {:ok, %{status: 201, body: created_commit}} <-
           GithubClient.create_commit(client, repo_connection.repo, %{
             message:
               "#{if(repo_connection.sync_direction == :pull, do: "[skip actions]")} Configure OpenFn",
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
    end
  end

  @spec push_pull_yml_to_default_branch(
          client :: Tesla.Client.t(),
          repo_connection :: ProjectRepoConnection.t()
        ) :: {:ok, Tesla.Env.t()} | {:error, Tesla.Env.t() | GithubError.t()}
  defp push_pull_yml_to_default_branch(client, repo_connection) do
    with {:ok, %{status: 200, body: %{"default_branch" => default_branch}}} <-
           GithubClient.get_repo(client, repo_connection.repo),
         {:ok, %{status: 201, body: pull_blob}} <-
           GithubClient.create_blob(client, repo_connection.repo, %{
             content: pull_yml()
           }),
         {:ok, %{status: 200, body: base_commit}} <-
           GithubClient.get_commit(
             client,
             repo_connection.repo,
             "heads/#{default_branch}"
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
               }
             ]
           }),
         {:ok, %{status: 201, body: created_commit}} <-
           GithubClient.create_commit(client, repo_connection.repo, %{
             message: "[skip actions] Configure OpenFn: pull workflow",
             tree: created_tree["sha"],
             parents: [base_commit["sha"]]
           }),
         {:ok, %{status: 200, body: updated_ref}} <-
           GithubClient.update_ref(
             client,
             repo_connection.repo,
             "heads/#{default_branch}",
             %{sha: created_commit["sha"]}
           ) do
      {:ok, updated_ref}
    end
  end

  defp maybe_create_config_blob(tesla_client, repo_connection) do
    if is_nil(repo_connection.config_path) do
      GithubClient.create_blob(tesla_client, repo_connection.repo, %{
        content: config_json(repo_connection)
      })
    else
      {:ok, nil}
    end
  end

  defp maybe_include_config_tree(repo_connection, config_blob_or_nil) do
    if is_struct(config_blob_or_nil, Tesla.Env) do
      [
        %{
          path: config_target_path(repo_connection),
          mode: "100644",
          type: "blob",
          sha: config_blob_or_nil.body["sha"]
        }
      ]
    else
      []
    end
  end

  defp pull_yml do
    :code.priv_dir(:lightning)
    |> Path.join("github/pull.yml")
    |> File.read!()
  end

  defp deploy_yml(repo_connection) do
    :code.priv_dir(:lightning)
    |> Path.join("github/deploy.yml")
    |> EEx.eval_file(
      assigns: [
        project_id: repo_connection.project_id,
        config_path: config_target_path(repo_connection),
        api_secret_name: api_secret_name(repo_connection),
        branch: repo_connection.branch
      ]
    )
  end

  defp config_json(repo_connection) do
    Jason.encode!(
      %{
        endpoint: LightningWeb.Endpoint.url(),
        statePath: "openfn-#{repo_connection.project_id}-state.json",
        specPath: "openfn-#{repo_connection.project_id}-spec.yaml"
      },
      pretty: true
    )
  end

  defp pull_yml_target_path do
    ".github/workflows/openfn-pull.yml"
  end

  defp deploy_yml_target_path(repo_connection) do
    ".github/workflows/openfn-#{repo_connection.project_id}-deploy.yml"
  end

  defp config_target_path(repo_connection) do
    path = ProjectRepoConnection.config_path(repo_connection)

    # get rid of ./ because we always operate from root
    Path.relative_to(path, ".")
  end

  defp api_secret_name(repo_connection) do
    sanitized_id = String.replace(repo_connection.project_id, "-", "_")
    "OPENFN_#{sanitized_id}_API_KEY"
  end

  defp undo_repo_actions(repo_connection, user) do
    with {:ok, access_token} <- fetch_user_access_token(user),
         {:ok, client} <- GithubClient.build_bearer_client(access_token) do
      maybe_delete_file(
        client,
        repo_connection,
        deploy_yml_target_path(repo_connection)
      )

      maybe_delete_file(
        client,
        repo_connection,
        config_target_path(repo_connection)
      )

      GithubClient.delete_repo_secret(
        client,
        repo_connection.repo,
        api_secret_name(repo_connection)
      )
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
          message: "[skip actions] Disconnect OpenFn: delete #{file_path}",
          branch: repo_connection.branch
        }
      )
    end
  end

  defp configure_api_secret(client, repo_connection) do
    with {:ok, %{status: 200, body: resp_body}} <-
           GithubClient.get_repo_public_key(client, repo_connection.repo) do
      public_key = Base.decode64!(resp_body["key"])

      encrypted_secret =
        :enacl.box_seal(repo_connection.access_token, public_key)

      GithubClient.create_repo_secret(
        client,
        repo_connection.repo,
        api_secret_name(repo_connection),
        %{
          encrypted_value: Base.encode64(encrypted_secret),
          key_id: resp_body["key_id"]
        }
      )
    end
  end

  @spec configure_github_repo(ProjectRepoConnection.t(), User.t()) ::
          :ok | {:error, map()}
  defp configure_github_repo(repo_connection, user) do
    with {:ok, user_token} <- fetch_user_access_token(user),
         {:ok, tesla_client} <- GithubClient.build_bearer_client(user_token),
         {:ok, _} <-
           push_pull_yml_to_default_branch(tesla_client, repo_connection),
         {:ok, _} <-
           push_files_to_selected_branch(tesla_client, repo_connection),
         {:ok, _} <- configure_api_secret(tesla_client, repo_connection) do
      if repo_connection.sync_direction == :pull do
        initiate_sync(repo_connection, user.email)
      else
        :ok
      end
    end
  end

  defp verify_file_exists(client, repo, branch, file_path) do
    case GithubClient.get_repo_content(
           client,
           repo,
           file_path,
           "heads/#{branch}"
         ) do
      {:ok, %{status: 200}} ->
        :ok

      _other ->
        {:error,
         GithubError.file_not_found(
           "#{file_path} does not exist in the #{branch} branch"
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
