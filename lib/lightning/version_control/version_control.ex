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

  def add_github_repo_and_branch(project_id, repo, branch) do
    pending_installation =
      Repo.one!(
        from(prc in ProjectRepoConnection,
          where: prc.project_id == ^project_id
        )
      )

    pending_installation
    |> ProjectRepoConnection.changeset(%{repo: repo, branch: branch})
    |> Repo.update()
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
end
