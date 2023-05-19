defmodule Lightning.Policies.Provisioning do
  @moduledoc """
  The Bodyguard Policy module for users roles.
  """
  @behaviour Bodyguard.Policy

  alias Lightning.Accounts.User
  alias Lightning.Projects
  alias Lightning.Projects.Project

  @type actions :: :provision_project

  @doc """
  authorize/3 takes an action, a user, and a project. It checks the user's role
  for this project and returns `true` if the user can perform the action and
  false if they cannot.

  Note that permissions are grouped by action.

  We deny by default, so if a user's role is not added to the allow roles list
  for a particular action they are denied.
  """
  @spec authorize(actions(), Lightning.Accounts.User.t(), Project.t()) :: boolean
  def authorize(:provision_project, %User{role: role}, %Project{id: nil}) do
    role in [:superuser]
  end

  def authorize(:provision_project, %User{} = user, %Project{} = project) do
    Projects.get_project_user_role(user, project) in [
      :owner,
      :admin,
      :editor
    ]
  end

  def authorize(_, _, _), do: false
end
