defmodule Lightning.Policies.Workflows do
  @moduledoc """
  The Bodyguard Policy module for Workflows API.
  """
  @behaviour Bodyguard.Policy

  alias Lightning.Accounts.User
  alias Lightning.Projects.Project
  alias Lightning.Run

  @type actions :: :access_write | :access_read
  @spec authorize(actions(), User.t() | Runt.t(), Project.t()) ::
          :ok | {:error, :unauthorized}
  def authorize(access, %User{} = user, project)
      when access in [:access_write, :access_read] do
    Lightning.Policies.Permissions.can(
      Lightning.Policies.ProjectUsers,
      :access_project,
      user,
      project
    )
  end

  def authorize(access, %Run{} = run, project)
      when access in [:access_write, :access_read] do
    Lightning.Runs.get_project_id_for_run(run) == project.id
  end
end
