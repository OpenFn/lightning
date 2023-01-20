defmodule Lightning.Projects.Policy do
  @moduledoc """
  The Bodyguard Policy module.
  """
  @behaviour Bodyguard.Policy

  alias Lightning.Accounts.User
  alias Lightning.Projects
  alias Lightning.Projects.Project

  # Users with admin level access to a project ccan access project settings with read/write rights
  def authorize(action, %User{} = user, %Project{} = project)
      when action in [:edit] do
    Projects.get_project_user_role(user, project) == :admin
  end

  # Project members can read a project
  def authorize(action, user, %Project{id: _id} = project)
      when action in [:read, :index] do
    Projects.is_member_of?(project, user)
  end

  # Super users can do anything
  def authorize(_action, %User{role: :superuser}, _params), do: true

  # Default deny
  def authorize(_, _user, _project), do: false
end
