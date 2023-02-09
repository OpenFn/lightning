defmodule Lightning.Policies.ProjectUsers do
  @moduledoc """
  The Bodyguard Policy module for projects members roles.
  """
  @behaviour Bodyguard.Policy

  alias Lightning.Projects
  alias Lightning.Projects.Project
  alias Lightning.Accounts.User

  @type actions :: :edit_jobs

  @doc """
  authorize/3 takes an action, a user, and a project. It checks the user's role
  for this project and returns `true` if the user can perform the action in
  that project and `false` if they cannot.

  Note that permissions are grouped by action, rather than by user role.

  We deny by default, so if a user's role is not added to the allow roles list
  for a particular action they are denied.
  """
  @spec authorize(
          actions(),
          Lightning.Accounts.User.t(),
          Lightning.Projects.Project.t()
        ) :: boolean
  def authorize(:edit_jobs, %User{} = user, %Project{} = project) do
    Projects.get_project_user_role(user, project) in [:admin, :editor, :owner]
  end
end
