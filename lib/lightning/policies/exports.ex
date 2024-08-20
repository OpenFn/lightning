defmodule Lightning.Policies.Exports do
  @moduledoc """
  The Bodyguard Policy module for Exports
  """
  @behaviour Bodyguard.Policy

  alias Lightning.Accounts.User
  alias Lightning.Projects
  alias Lightning.Projects.Project
  alias Lightning.Projects.File, as: ProjectFile

  @type actions :: :download

  @spec authorize(actions(), User.t(), Project.t()) ::
          boolean() | {:error, :forbidden}
  def authorize(:download, %User{} = user, %ProjectFile{project_id: project_id}) do
    Projects.member_of?(%Project{id: project_id}, user) or {:error, :forbidden}
  end
end
