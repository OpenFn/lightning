defmodule Lightning.VersionControl do
  @moduledoc """
  Boundary module for handling Version control activities for project, jobs
  workflows etc
  Use this module to create, modify and delete connections as well
  as running any associated sync jobs
  """

  import Ecto.Query, warn: false
  alias Lightning.Repo
  alias Lightning.VersionControl.ProjectRepo
  alias Lightning.VersionControl.GithubClient

  @doc """
  Creates a connection between a project and a github repo
  """
  def create_github_connection(attrs) do
    %ProjectRepo{}
    |> ProjectRepo.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Deletes a github connection used when re installing
  """
  def remove_github_connection(project_id) do
    Repo.one(from(p in ProjectRepo, where: p.project_id == ^project_id))
    |> Repo.delete()
  end

  def get_repo_connection(project_id) do
    Repo.one(from(p in ProjectRepo, where: p.project_id == ^project_id))
  end

  def add_github_installation_id(user_id, installation_id) do
    pending_installation =
      Repo.one(
        from(p in ProjectRepo,
          where: p.user_id == ^user_id and is_nil(p.github_installation_id)
        )
      )

    pending_installation
    |> ProjectRepo.changeset(%{github_installation_id: installation_id})
    |> Repo.update()
  end

  def add_github_repo_and_branch(project_id, repo, branch) do
    pending_installation =
      Repo.one(
        from(p in ProjectRepo,
          where: p.project_id == ^project_id
        )
      )

    pending_installation
    |> ProjectRepo.changeset(%{repo: repo, branch: branch})
    |> Repo.update()
  end

  def fetch_installation_repos(project_id) do
    with %ProjectRepo{} = repo_connection <-
           Repo.get_by(ProjectRepo, project_id: project_id),
         {:ok, repos} <-
           GithubClient.installation_repos(
             repo_connection.github_installation_id
           ) do
      {:ok, repos}
    end
  end

  def fetch_repo_branches(project_id, repo_name) do
    with %ProjectRepo{} = repo_connection <-
           Repo.get_by(ProjectRepo, project_id: project_id),
         {:ok, branches} <-
           GithubClient.get_repo_branches(
             repo_connection.github_installation_id,
             repo_name
           ) do
      {:ok, branches}
    else
      _ -> {:ok, []}
    end
  end

  def run_sync(project_id, user_name) do
    with %ProjectRepo{} = repo_connection <-
           Repo.get_by(ProjectRepo, project_id: project_id) do
      GithubClient.fire_repository_dispatch(
        repo_connection.github_installation_id,
        repo_connection.repo,
        user_name
      )
    end
  end

  def github_enabled?() do
    Application.get_env(:lightning, :github_app, [])
    |> then(fn config ->
      Keyword.get(config, :cert) && Keyword.get(config, :app_id)
    end)
  end
end
