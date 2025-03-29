defmodule Lightning.Policies.Exports do
  @moduledoc """
  The Bodyguard Policy module for Exports
  """
  @behaviour Bodyguard.Policy

  alias Lightning.Accounts.User
  alias Lightning.Policies.ProjectUsers
  alias Lightning.Projects
  alias Lightning.Projects.File, as: ProjectFile
  alias Lightning.Projects.Project

  @type actions :: :download

  @spec authorize(actions(), User.t(), ProjectFile.t()) ::
          boolean() | {:error, :forbidden}
  def authorize(:download, %User{} = user, %ProjectFile{project_id: project_id}) do
    Projects.member_of?(%Project{id: project_id}, user) or
      ProjectUsers.allow_as_support_user?(user, project_id) or
      {:error, :forbidden}
  end
end
