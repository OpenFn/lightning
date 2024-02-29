defmodule Lightning.VersionControl do
  @moduledoc """
  Boundary module for handling Version control activities for project, jobs
  workflows etc
  Use this module to create, modify and delete connections as well
  as running any associated sync jobs
  """

  import Ecto.Query, warn: false

  alias Lightning.Repo
  alias Lightning.VersionControl.GithubClient
  alias Lightning.VersionControl.GithubError
  alias Lightning.VersionControl.ProjectRepoConnection

  @doc """
  Creates a connection between a project and a github repo
  """
  def create_github_connection(attrs) do
    changeset = ProjectRepoConnection.changeset(%ProjectRepoConnection{}, attrs)
    user_id = Ecto.Changeset.get_field(changeset, :user_id)

    pending_installation = user_id && get_pending_user_installation(user_id)

    if is_nil(pending_installation) do
      Repo.insert(changeset)
    else
      changeset
      |> Ecto.Changeset.add_error(:user_id, "user has pending installation")
      |> Ecto.Changeset.apply_action(:insert)
    end
  end

  @doc """
  Deletes a github connection used when re installing
  """
  def remove_github_connection(project_id) do
    Repo.one(
      from(prc in ProjectRepoConnection, where: prc.project_id == ^project_id)
    )
    |> Repo.delete()
  end

  def get_repo_connection(project_id) do
    Repo.one(
      from(prc in ProjectRepoConnection, where: prc.project_id == ^project_id)
    )
  end

  @spec get_pending_user_installation(Ecto.UUID.t()) ::
          ProjectRepoConnection.t() | nil
  def get_pending_user_installation(user_id) do
    query =
      from(prc in ProjectRepoConnection,
        where: prc.user_id == ^user_id and is_nil(prc.github_installation_id)
      )

    Repo.one(query)
  end

  def add_github_installation_id(user_id, installation_id) do
    pending_installation =
      Repo.one!(
        from(prc in ProjectRepoConnection,
          where: prc.user_id == ^user_id and is_nil(prc.github_installation_id)
        )
      )

    pending_installation
    |> ProjectRepoConnection.changeset(%{github_installation_id: installation_id})
    |> Repo.update()
  end

  def connect_github_repo(project_id, repo, branch) do
    installation =
      Repo.one!(
        from(prc in ProjectRepoConnection,
          where:
            prc.project_id == ^project_id and
              not is_nil(prc.github_installation_id)
        )
      )

    case push_workflow_files(installation.github_installation_id, repo, branch) do
      {:ok, _result} ->
        installation
        |> ProjectRepoConnection.changeset(%{repo: repo, branch: branch})
        |> Repo.update()

      {:error, %Tesla.Env{body: body}} ->
        {:error, body}

      {:error, other} ->
        {:error, other}
    end
  end

  def fetch_installation_repos(project_id) do
    with %ProjectRepoConnection{} = repo_connection <-
           Repo.get_by(ProjectRepoConnection, project_id: project_id) do
      GithubClient.installation_repos(repo_connection.github_installation_id)
    end
  end

  def fetch_repo_branches(project_id, repo_name) do
    with %ProjectRepoConnection{} = repo_connection <-
           Repo.get_by(ProjectRepoConnection, project_id: project_id) do
      GithubClient.get_repo_branches(
        repo_connection.github_installation_id,
        repo_name
      )
    end
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

  def github_enabled? do
    Application.get_env(:lightning, :github_app, [])
    |> then(fn config ->
      Keyword.get(config, :cert) && Keyword.get(config, :app_id)
    end)
  end

  @spec push_workflow_files(
          installation_id :: String.t(),
          repo :: String.t(),
          branch :: String.t()
        ) :: {:ok, Tesla.Env.t()} | {:error, Tesla.Env.t() | GithubError.t()}
  defp push_workflow_files(installation_id, repo, branch) do
    with {:ok, client} <- GithubClient.build_client(installation_id),
         {:ok, %{status: 201, body: pull_blob}} <-
           GithubClient.create_blob(client, repo, %{content: pull_yml()}),
         {:ok, %{status: 201, body: deploy_blob}} <-
           GithubClient.create_blob(client, repo, %{content: deploy_yml()}),
         {:ok, %{status: 200, body: base_commit}} <-
           GithubClient.get_commit(client, repo, "heads/#{branch}"),
         {:ok, %{status: 201, body: created_tree}} <-
           GithubClient.create_tree(client, repo, %{
             base_tree: base_commit["commit"]["tree"]["sha"],
             tree: [
               %{
                 path: ".github/workflows/pull.yml",
                 mode: "100644",
                 type: "blob",
                 sha: pull_blob["sha"]
               },
               %{
                 path: ".github/workflows/deploy.yml",
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
           GithubClient.update_ref(client, repo, "heads/#{branch}", %{
             sha: created_commit["sha"]
           }) do
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
end
