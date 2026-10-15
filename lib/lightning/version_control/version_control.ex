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
  alias Lightning.Projects
  alias Lightning.Repo
  alias Lightning.VersionControl.Audit
  alias Lightning.VersionControl.Events
  alias Lightning.VersionControl.GithubClient
  alias Lightning.VersionControl.GithubError
  alias Lightning.VersionControl.ProjectRepoConnection
  alias Lightning.VersionControl.VersionControlUsageLimiter
  alias Lightning.Workflows.Workflow

  require Logger

  @doc "Subscribes to a user's version control events, such as a failed OAuth token refresh."
  defdelegate subscribe(user), to: Events

  @doc """
  Creates a connection between a project and a github repo.

  The `(root_project_id, repo, branch)` uniqueness constraint on
  `project_repo_connections` is the source of truth: two concurrent inserts
  for the same project family + (repo, branch) cannot both succeed even at
  READ COMMITTED isolation. The constraint violation is translated back into
  `:branch_used_in_project_tree` for callers.
  """
  @spec create_github_connection(map(), User.t()) ::
          {:ok, ProjectRepoConnection.t()}
          | {:error,
             Ecto.Changeset.t()
             | UsageLimiting.message()
             | :branch_used_in_project_tree
             | binary()}
  def create_github_connection(attrs, user) do
    changeset =
      ProjectRepoConnection.create_changeset(%ProjectRepoConnection{}, attrs)

    Repo.transact(fn ->
      with {:ok, repo_connection} <- insert_repo_connection(changeset),
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

  defp insert_repo_connection(changeset) do
    case Repo.insert(changeset) do
      {:ok, repo_connection} ->
        {:ok, repo_connection}

      {:error, %Ecto.Changeset{} = failed} ->
        if ProjectRepoConnection.tree_unique_violation?(failed) do
          {:error, :branch_used_in_project_tree}
        else
          {:error, failed}
        end
    end
  end

  # `binary()` because this reaches `initiate_sync/2`, whose export pre-flight
  # fails with a plain string naming the colliding entities.
  @spec reconfigure_github_connection(ProjectRepoConnection.t(), map(), User.t()) ::
          :ok | {:error, UsageLimiting.message() | map() | binary()}
  def reconfigure_github_connection(repo_connection, params, user) do
    changeset =
      ProjectRepoConnection.reconfigure_changeset(repo_connection, params)

    Repo.transact(fn ->
      with :ok <-
             VersionControlUsageLimiter.limit_github_sync(
               repo_connection.project_id
             ),
           {:ok, updated_repo_connection} <- save_reconfigured(changeset, user),
           :ok <- configure_github_repo(updated_repo_connection, user) do
        {:ok, updated_repo_connection}
      end
    end)
    |> case do
      {:ok, _updated} -> :ok
      error -> error
    end
  end

  # Only a new workspace folder is stored, the rest is virtual
  defp save_reconfigured(%{changes: %{workspace_path: _}} = changeset, user) do
    with {:ok, updated} <- Repo.update(changeset),
         {:ok, _audit} <-
           changeset.data
           |> Audit.repo_connection_updated(updated, user)
           |> Repo.insert() do
      {:ok, updated}
    end
  end

  defp save_reconfigured(changeset, _user),
    do: Ecto.Changeset.apply_action(changeset, :update)

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
         :ok <- maybe_verify_config_exists(client, repo_connection) do
      verify_repo_secret_exists(
        client,
        repo_connection,
        api_secret_name(repo_connection)
      )
    end
  end

  # v2 has no config file: the CLI owns the workspace, see get_sync_status/1
  defp maybe_verify_config_exists(_client, %{sync_version: true}), do: :ok

  defp maybe_verify_config_exists(client, repo_connection) do
    verify_file_exists(
      client,
      repo_connection.repo,
      repo_connection.branch,
      config_target_path(repo_connection)
    )
  end

  @doc """
  Reports how a v2 connection's branch is doing:

  - `tracking`: which project the branch's CLI checkout belongs to.
    `:pending` until the first pull commits it, `{:other_project, uuid}` when
    the branch tracks a different project.
  - `last_pull` / `last_deploy`: the latest run of each GitHub workflow, or nil.
  """
  @spec get_sync_status(ProjectRepoConnection.t()) ::
          {:ok, map()} | {:error, GithubError.t() | Tesla.Env.t() | term()}
  def get_sync_status(repo_connection) do
    %{repo: repo, branch: branch, project_id: project_id} = repo_connection

    with {:ok, client} <-
           GithubClient.build_installation_client(
             repo_connection.github_installation_id
           ),
         {:ok, workspace} <- workspace_state(client, repo_connection),
         # openfn-pull.yml is shared by every project in the repo, so pick this
         # project's runs by the run-name set in pull_v2.yml.
         {:ok, last_pull} <-
           latest_run(
             client,
             repo,
             Path.basename(pull_yml_target_path()),
             [event: "workflow_dispatch", per_page: 30],
             &String.contains?(&1["display_title"] || "", project_id)
           ),
         {:ok, last_deploy} <-
           latest_run(
             client,
             repo,
             Path.basename(deploy_yml_target_path(repo_connection)),
             branch: branch,
             per_page: 1
           ) do
      {:ok,
       Map.merge(workspace, %{last_pull: last_pull, last_deploy: last_deploy})}
    end
  end

  @doc """
  What a not-yet-connected v2 workspace already holds on the branch: the
  `tracking` and `projects` of `get_sync_status/1`. Checks `user` can access
  the installation first, as `fetch_repo_branches/3` does.
  """
  @spec check_workspace(User.t(), ProjectRepoConnection.t()) ::
          {:ok, map()} | {:error, term()}
  def check_workspace(user, repo_connection) do
    installation_id = repo_connection.github_installation_id

    with :ok <- authorize_installation_access(user, installation_id),
         {:ok, client} <-
           GithubClient.build_installation_client(installation_id) do
      workspace_state(client, repo_connection)
    end
  end

  defp workspace_state(client, repo_connection) do
    with {:ok, tracking} <- tracking_status(client, repo_connection),
         {:ok, projects} <- workspace_projects(client, repo_connection) do
      {:ok, %{tracking: tracking, projects: projects}}
    end
  end

  # The CLI keeps a copy of each project it pulls at
  # <workspace>/.projects/<alias>@<host>.yaml, with the uuid inside.
  # ponytail: one request per copy, fine for the handful a workspace holds
  defp workspace_projects(client, %{repo: repo, branch: branch} = connection) do
    dir = ProjectRepoConnection.workspace_file(connection, ".projects")

    case GithubClient.get_repo_content(client, repo, dir, "heads/#{branch}") do
      {:ok, %{body: entries}} when is_list(entries) ->
        entries
        |> Enum.flat_map(fn entry ->
          case Regex.run(~r/\A([^@]+)@(.+)\.ya?ml\z/, entry["name"]) do
            [_name, alias, host] ->
              [%{alias: alias, host: host, path: entry["path"]}]

            nil ->
              []
          end
        end)
        |> Enum.reduce_while({:ok, []}, fn project, {:ok, acc} ->
          case project_identity(client, repo, project.path, branch) do
            {:ok, identity} ->
              {:cont, {:ok, acc ++ [Map.merge(project, identity)]}}

            error ->
              {:halt, error}
          end
        end)

      {:ok, _not_a_dir} ->
        {:ok, []}

      {:error, %Tesla.Env{status: 404}} ->
        {:ok, []}

      error ->
        error
    end
  end

  defp project_identity(client, repo, path, branch) do
    with {:ok, %{body: %{"content" => content}}} <-
           GithubClient.get_repo_content(client, repo, path, "heads/#{branch}") do
      with {:ok, yaml} <- Base.decode64(content, ignore: :whitespace),
           {:ok, project} <- YamlElixir.read_from_string(yaml) do
        {:ok,
         %{uuid: get_in(project, ["openfn", "uuid"]), name: project["name"]}}
      else
        _invalid -> {:ok, %{uuid: nil, name: nil}}
      end
    end
  end

  defp tracking_status(client, %{branch: branch} = repo_connection) do
    case GithubClient.get_repo_content(
           client,
           repo_connection.repo,
           checkout_path(repo_connection),
           "heads/#{branch}"
         ) do
      {:ok, %{body: %{"content" => content}}} ->
        with {:ok, yaml} <- Base.decode64(content, ignore: :whitespace),
             {:ok, checkout} <- YamlElixir.read_from_string(yaml) do
          uuid = checkout["uuid"]

          {:ok,
           if(uuid == repo_connection.project_id,
             do: :ok,
             else: {:other_project, uuid}
           )}
        else
          _invalid -> {:error, :invalid_checkout}
        end

      {:error, %Tesla.Env{status: 404}} ->
        {:ok, :pending}

      error ->
        error
    end
  end

  # Written by `openfn project pull/deploy`, see @openfn/project util/config.ts
  defp checkout_path(%{branch: branch} = repo_connection) do
    ProjectRepoConnection.workspace_file(
      repo_connection,
      ".openfn/branches/#{branch}/checkout.yaml"
    )
  end

  defp latest_run(client, repo, workflow_file, query, match \\ fn _ -> true end) do
    with {:ok, %{body: %{"workflow_runs" => runs}}} <-
           GithubClient.list_workflow_runs(client, repo, workflow_file, query) do
      {:ok, runs |> Enum.find(match) |> run_summary()}
    end
  end

  defp run_summary(nil), do: nil

  defp run_summary(run) do
    %{
      status: run["status"],
      conclusion: run["conclusion"],
      url: run["html_url"],
      created_at: parse_datetime(run["created_at"])
    }
  end

  defp parse_datetime(iso8601) do
    case DateTime.from_iso8601(iso8601 || "") do
      {:ok, datetime, _offset} -> datetime
      _error -> nil
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

  @doc """
  Fires the GitHub Action that pulls the project spec and commits it.

  The export runs here first and its result is thrown away. The Action fetches
  `/api/provision/:id.yaml`, and a 400 there lands in a GitHub Actions log
  Lightning cannot read, so the user sees a sync that failed with no reason.
  Costs one extra full spec generation on every successful sync.
  """
  @spec initiate_sync(
          repo_connection :: ProjectRepoConnection.t(),
          commit_message :: String.t()
        ) :: :ok | {:error, UsageLimiting.message() | map() | binary()}
  def initiate_sync(repo_connection, commit_message) do
    with :ok <-
           VersionControlUsageLimiter.limit_github_sync(
             repo_connection.project_id
           ),
         snapshots <-
           list_snapshots_for_project(repo_connection),
         {:ok, _spec} <-
           Projects.export_project(
             :yaml,
             repo_connection.project_id,
             snapshot_ids_for_export(snapshots),
             :v1
           ),
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
               inputs: pull_inputs(repo_connection, commit_message, snapshots)
             }
           ) do
      :ok
    end
  end

  # v2 pulls the live project with `openfn project pull`, which has no
  # snapshot or config path options
  defp pull_inputs(%{sync_version: true} = repo_connection, commit_message, _) do
    %{
      projectId: repo_connection.project_id,
      apiSecretName: api_secret_name(repo_connection),
      endpoint: LightningWeb.Endpoint.url(),
      branch: repo_connection.branch,
      workspace: ProjectRepoConnection.workspace_path(repo_connection),
      commitMessage: commit_message
    }
    |> maybe_put_alias(repo_connection.local_alias)
  end

  defp pull_inputs(repo_connection, commit_message, snapshots) do
    %{
      projectId: repo_connection.project_id,
      apiSecretName: api_secret_name(repo_connection),
      pathToConfig: config_target_path(repo_connection),
      branch: repo_connection.branch,
      commitMessage: commit_message
    }
    |> maybe_add_snapshots(snapshots)
  end

  # Only the first pull needs it: the CLI keeps the alias of a local copy
  defp maybe_put_alias(inputs, nil), do: inputs
  defp maybe_put_alias(inputs, alias), do: Map.put(inputs, :alias, alias)

  defp list_snapshots_for_project(%{project_id: project_id}) do
    current_query =
      from w in Workflow,
        join: s in assoc(w, :snapshots),
        on: s.lock_version == w.lock_version,
        where: w.project_id == ^project_id and is_nil(w.deleted_at),
        order_by: s.id,
        select: s.id

    Repo.all(current_query)
  end

  # Mirrors maybe_add_snapshots/2 below: an empty list means the Action fetches
  # the current workflows rather than a set of snapshots, so the pre-flight has
  # to ask for the same spec the Action will.
  defp snapshot_ids_for_export([]), do: nil
  defp snapshot_ids_for_export(snapshot_ids), do: snapshot_ids

  defp export_preflight(repo_connection) do
    Projects.export_project(
      :yaml,
      repo_connection.project_id,
      repo_connection
      |> list_snapshots_for_project()
      |> snapshot_ids_for_export(),
      :v1
    )
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

  @doc """
  Fetches a repository's branches for `user`.

  The GitHub App private key can mint an installation token for **any**
  installation of the shared App, so this verifies (using the user's own GitHub
  OAuth grant, via `/user/installations`) that `installation_id` is one the user
  can access before using the app credential. Without this check a user could
  read branch names from a private repository in another tenant's installation
  (a confused-deputy). GitHub's installation token then scopes repository access
  to that installation.
  """
  def fetch_repo_branches(user, installation_id, repo_name) do
    with :ok <- authorize_installation_access(user, installation_id),
         {:ok, client} <- GithubClient.build_installation_client(installation_id) do
      case GithubClient.get_repo_branches(client, repo_name) do
        {:ok, %{body: body}} ->
          {:ok, body}

        {:error, %{body: body}} ->
          {:error, body}
      end
    end
  end

  defp authorize_installation_access(user, installation_id) do
    case fetch_user_installations(user) do
      {:ok, %{"installations" => installations}} when is_list(installations) ->
        if Enum.any?(installations, fn installation ->
             to_string(installation["id"]) == to_string(installation_id)
           end) do
          :ok
        else
          {:error, :unauthorized_installation}
        end

      {:ok, _body} ->
        {:error, :unauthorized_installation}

      {:error, _reason} = error ->
        error
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
             message: configure_commit_message(repo_connection),
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

  defp configure_commit_message(%{sync_direction: :pull}),
    do: "[skip actions] Configure OpenFn"

  defp configure_commit_message(%{sync_version: true}),
    do: "Configure OpenFn [openfn force]"

  defp configure_commit_message(_repo_connection), do: "Configure OpenFn"

  @spec push_pull_yml_to_default_branch(
          client :: Tesla.Client.t(),
          repo_connection :: ProjectRepoConnection.t()
        ) :: {:ok, Tesla.Env.t()} | {:error, Tesla.Env.t() | GithubError.t()}
  defp push_pull_yml_to_default_branch(client, repo_connection) do
    with {:ok, %{status: 200, body: %{"default_branch" => default_branch}}} <-
           GithubClient.get_repo(client, repo_connection.repo),
         {:ok, %{status: 201, body: pull_blob}} <-
           GithubClient.create_blob(client, repo_connection.repo, %{
             content: pull_yml(repo_connection)
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

  # v2 workspaces (openfn.yaml and friends) are written by the CLI, not here
  defp maybe_create_config_blob(_tesla_client, %{sync_version: true}),
    do: {:ok, nil}

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

  defp pull_yml(repo_connection) do
    :code.priv_dir(:lightning)
    |> Path.join(github_template("pull", repo_connection))
    |> File.read!()
  end

  defp deploy_yml(repo_connection) do
    :code.priv_dir(:lightning)
    |> Path.join(github_template("deploy", repo_connection))
    |> EEx.eval_file(
      assigns: [
        project_id: repo_connection.project_id,
        config_path: config_target_path(repo_connection),
        api_secret_name: api_secret_name(repo_connection),
        branch: repo_connection.branch,
        workspace: ProjectRepoConnection.workspace_path(repo_connection),
        workspace_glob:
          ProjectRepoConnection.workspace_file(repo_connection, "**"),
        endpoint: LightningWeb.Endpoint.url()
      ]
    )
  end

  # v2 sync uses @v2 of the GitHub actions (openfn.yaml workspaces)
  defp github_template(name, %{sync_version: true}), do: "github/#{name}_v2.yml"
  defp github_template(name, _repo_connection), do: "github/#{name}.yml"

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

      # v2's openfn.yaml belongs to the CLI workspace, so leave it in place
      if !repo_connection.sync_version do
        maybe_delete_file(
          client,
          repo_connection,
          config_target_path(repo_connection)
        )
      end

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
          :ok | {:error, map() | binary()}
  defp configure_github_repo(repo_connection, user) do
    # Before anything is written to the repo. This path pushes pull.yml, the
    # workflow files and the API secret before it reaches initiate_sync/2, so a
    # project whose names collide would otherwise leave a modified GitHub repo
    # behind and no connection row to show for it.
    with {:ok, _spec} <- export_preflight(repo_connection),
         {:ok, user_token} <- fetch_user_access_token(user),
         {:ok, tesla_client} <- GithubClient.build_bearer_client(user_token),
         {:ok, _} <-
           push_pull_yml_to_default_branch(tesla_client, repo_connection),
         # The secret goes in before the deploy workflow, which can run as
         # soon as it lands on the branch
         {:ok, _} <- configure_api_secret(tesla_client, repo_connection),
         {:ok, _} <-
           push_files_to_selected_branch(tesla_client, repo_connection) do
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
