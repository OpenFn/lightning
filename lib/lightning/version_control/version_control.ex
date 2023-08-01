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

  def add_github_installation_id(user_id, installation_id) do
    pending_installation =
      Repo.one(
        from p in ProjectRepo,
          where: p.user_id == ^user_id and is_nil(p.github_installation_id)
      )

    pending_installation
    |> ProjectRepo.changeset(%{github_installation_id: installation_id})
    |> Repo.update()
  end

  def fetch_installation_repos(installation_id) do
    {:ok, repos} = GithubClient.get_installation_repos(installation_id)

    {:ok, repos}
  end

  def fetch_repo_branches(installation_id, repo_name) do
    {:ok, branches} = GithubClient.get_repo_branches(installation_id, repo_name)

    {:ok, branches}
  end
end
