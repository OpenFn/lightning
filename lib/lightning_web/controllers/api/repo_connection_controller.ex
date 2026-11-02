defmodule LightningWeb.API.RepoConnectionController do
  @moduledoc """
  A project's connection to a GitHub repository, a singleton under the project.

      GET    /api/projects/:project_id/repo_connection
      PUT    /api/projects/:project_id/repo_connection        {"github_installation_id", "repo", "branch", …}
      DELETE /api/projects/:project_id/repo_connection
      POST   /api/projects/:project_id/repo_connection/syncs  {"commit_message": "…"}

  Open only to people: any member reads it, owners and admins connect and
  disconnect it, and editors and above start a sync. Connecting and
  disconnecting write to the repo with the caller's own GitHub account, so a
  caller who hasn't connected one is refused them.

  Lightning checks the repo on GitHub for `GET`, and a GitHub it can't reach
  doesn't fail the request: `verified` is `false` and `problems` holds
  `github_unavailable`. A write answers `verified: true` without reading the
  repo back, since it has just written every part. The token Lightning stores
  in the repo is never returned.
  """
  use LightningWeb, :controller

  import Ecto.Changeset

  alias Lightning.Extensions.Message
  alias Lightning.Projects.Project
  alias Lightning.VersionControl
  alias Lightning.VersionControl.GithubError
  alias Lightning.VersionControl.ProjectRepoConnection
  alias LightningWeb.API.Errors
  alias LightningWeb.API.FallbackController
  alias LightningWeb.API.Problem
  alias LightningWeb.API.Request
  alias LightningWeb.API.Target
  alias LightningWeb.Plugs.AuthorizeAction

  action_fallback FallbackController

  plug AuthorizeAction,
       {:repo_connections, :see_repo_connection}
       when action == :show

  plug AuthorizeAction,
       {:repo_connections, :write_repo_connection}
       when action in [:update, :delete]

  plug AuthorizeAction,
       {:repo_connections, :sync_repo_connection}
       when action == :sync

  @see {:repo_connections, :see_repo_connection}
  @write {:repo_connections, :write_repo_connection}
  @sync {:repo_connections, :sync_repo_connection}

  @accepted [
    :github_installation_id,
    :repo,
    :branch,
    :sync_direction,
    :config_path
  ]
  @types %{
    github_installation_id: :string,
    repo: :string,
    branch: :string,
    sync_direction:
      Ecto.ParameterizedType.init(Ecto.Enum, values: [:pull, :deploy]),
    config_path: :string
  }
  @defaults %{
    github_installation_id: nil,
    repo: nil,
    branch: nil,
    sync_direction: :pull,
    config_path: nil
  }

  # Changing any of these needs a new connection: reconnecting keeps them.
  @identity [:github_installation_id, :repo, :branch, :config_path]

  @sync_accepted [:commit_message]

  @branch_taken {"is already connected to another project in this project's family",
                 code: :tree_branch_conflict}

  @spec show(Plug.Conn.t(), map()) :: Plug.Conn.t() | {:error, term()}
  def show(conn, _params) do
    with {:ok, project} <- project(conn, @see),
         {:ok, repo_connection} <- fetch(project) do
      problems =
        case VersionControl.check_github_connection(repo_connection) do
          {:ok, problems} -> problems
          {:error, _unreachable} -> [:github_unavailable]
        end

      render(conn, "show.json",
        repo_connection: repo_connection,
        problems: problems,
        conn: conn
      )
    end
  end

  @doc """
  Connects the project to the repo, answering 201, or replaces its connection,
  answering 200. Either way Lightning writes the GitHub workflows, config and
  secret to the repo again, and for `pull` starts a sync. A connection to the
  same installation, repo, branch and config path is reconnected; one that
  changes any of them is removed and created again, in one transaction.
  """
  @spec update(Plug.Conn.t(), map()) :: Plug.Conn.t() | {:error, term()}
  def update(conn, _params) do
    body = conn.body_params
    user = conn.assigns.current_resource

    with {:ok, project} <- project(conn, @write),
         :ok <- Request.check_object(body),
         :ok <- github_connected(user) do
      # Required fields are checked by the connection's own changeset, so a
      # field of the wrong type is reported once, here.
      request = cast({@defaults, @types}, body, Map.keys(@types))

      attrs =
        request
        |> apply_changes()
        |> Map.merge(%{project_id: project.id, accept: true})

      unknown = Request.unknown_keys(body, [], @accepted)

      case VersionControl.get_repo_connection_for_project(project.id) do
        nil ->
          create(conn, attrs, unknown ++ Errors.from_changeset(request))

        existing ->
          replace(
            conn,
            existing,
            attrs,
            unknown ++ Errors.from_changeset(request)
          )
      end
    end
  end

  defp create(conn, attrs, entries) do
    changeset =
      ProjectRepoConnection.configure_changeset(%ProjectRepoConnection{}, attrs)

    with :ok <- refuse(entries, changeset) do
      attrs
      |> VersionControl.create_github_connection(conn.assigns.current_resource)
      |> written(conn, :created)
    end
  end

  defp replace(conn, existing, attrs, entries) do
    if Map.take(existing, @identity) == Map.take(attrs, @identity) do
      changeset = ProjectRepoConnection.reconfigure_changeset(existing, attrs)

      with :ok <- refuse(entries, changeset) do
        existing
        |> VersionControl.reconfigure_github_connection(
          Map.take(attrs, [:sync_direction, :accept]),
          conn.assigns.current_resource
        )
        |> case do
          :ok -> written({:ok, existing}, conn, :ok)
          error -> written(error, conn, :ok)
        end
      end
    else
      # A v2 connection stays one, in the same workspace folder.
      attrs =
        Map.merge(attrs, Map.take(existing, [:sync_version, :workspace_path]))

      # Checked as if it were the connection it replaces, so the tree's
      # branch check doesn't count the old connection against it.
      changeset =
        ProjectRepoConnection.configure_changeset(
          %ProjectRepoConnection{id: existing.id},
          attrs
        )

      with :ok <- refuse(entries, changeset) do
        existing
        |> VersionControl.replace_github_connection(
          attrs,
          conn.assigns.current_resource
        )
        |> written(conn, :ok)
      end
    end
  end

  # A field the request refused for its type is missing from the changeset,
  # which would call it blank too, so the first entry at each place stands.
  defp refuse(entries, changeset) do
    (entries ++ Errors.from_changeset(changeset))
    |> Enum.uniq_by(&Map.drop(&1, [:code, :detail]))
    |> Errors.refuse()
  end

  defp written({:ok, repo_connection}, conn, status) do
    repo_connection =
      VersionControl.get_repo_connection_for_project(repo_connection.project_id)

    conn
    |> put_status(status)
    |> render("show.json",
      repo_connection: repo_connection,
      problems: nil,
      conn: conn
    )
  end

  # Another request connected the project since the lookup. Rerun the request
  # so it replaces that connection.
  defp written({:error, %Ecto.Changeset{} = changeset}, conn, _status) do
    if Keyword.has_key?(changeset.errors, :project_id),
      do: update(conn, conn.params),
      else: {:error, changeset}
  end

  defp written({:error, :branch_used_in_project_tree}, _conn, _status),
    do: Errors.refuse([Errors.entry([:branch], @branch_taken)])

  defp written({:error, error}, _conn, _status), do: github_error(error)

  @doc """
  Removes the connection and answers 204, then tries to remove the deploy
  workflow, config and secret from the repo, whether or not GitHub answers.
  """
  @spec delete(Plug.Conn.t(), map()) :: Plug.Conn.t() | {:error, term()}
  def delete(conn, _params) do
    user = conn.assigns.current_resource

    with {:ok, project} <- project(conn, @write),
         :ok <- github_connected(user),
         {:ok, repo_connection} <- fetch(project),
         {:ok, _removed} <-
           VersionControl.remove_github_connection(repo_connection, user) do
      send_resp(conn, :no_content, "")
    end
  end

  @doc """
  Starts the GitHub Action that commits the project to the branch, answering
  202 with no body once GitHub has it. `commit_message` defaults to one naming
  the caller.
  """
  @spec sync(Plug.Conn.t(), map()) :: Plug.Conn.t() | {:error, term()}
  def sync(conn, _params) do
    body = conn.body_params
    user = conn.assigns.current_resource

    with {:ok, project} <- project(conn, @sync),
         :ok <- Request.check_object(body),
         {:ok, repo_connection} <- fetch(project),
         {:ok, message} <- commit_message(body, user),
         :ok <- initiate_sync(repo_connection, message) do
      send_resp(conn, :accepted, "")
    end
  end

  defp commit_message(body, user) do
    request =
      {%{commit_message: nil}, %{commit_message: :string}}
      |> cast(body, [:commit_message])

    entries =
      Request.unknown_keys(body, [], @sync_accepted) ++
        Errors.from_changeset(request)

    with :ok <- Errors.refuse(entries) do
      {:ok,
       get_field(request, :commit_message) ||
         "user #{user.email} initiated a sync from Lightning"}
    end
  end

  defp initiate_sync(repo_connection, message) do
    case VersionControl.initiate_sync(repo_connection, message) do
      :ok -> :ok
      {:error, error} -> github_error(error)
    end
  end

  defp project(conn, permission),
    do:
      Target.project(
        conn.assigns.scope,
        Request.param(conn, "project_id"),
        permission
      )

  defp fetch(%Project{id: project_id}) do
    case VersionControl.get_repo_connection_for_project(project_id) do
      nil -> {:error, :not_found}
      repo_connection -> {:ok, repo_connection}
    end
  end

  # Connecting and disconnecting write to the repo as the caller.
  defp github_connected(%{github_oauth_token: nil}), do: {:error, :forbidden}
  defp github_connected(_user), do: :ok

  defp github_error(%Message{}), do: {:error, :exceeds_limit}
  defp github_error(:concurrent_edit), do: {:error, :concurrent_edit}

  # The caller's GitHub sign-in has lapsed, so they can't write to the repo.
  defp github_error(%GithubError{code: :invalid_oauth_token}),
    do: {:error, :forbidden}

  # The export Lightning runs before it writes to GitHub names the two items
  # that collide.
  defp github_error(message) when is_binary(message),
    do: {:error, Problem.new(:export_conflict)}

  defp github_error(_github_refused_or_unreachable),
    do: {:error, Problem.new(:service_unavailable)}
end
