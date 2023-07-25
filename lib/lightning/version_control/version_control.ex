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

  @doc """
  Creates a connection between a project and a github repo
  """
  def create_github_connection(attrs) do 
    %ProjectRepo{}
    |> ProjectRepo.changeset(attrs)
    |> Repo.insert()
  end
end

