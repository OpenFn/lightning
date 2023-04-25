defmodule Lightning.Policies.Projects do
  @moduledoc """
  The Bodyguard Policy module.
  """
  @behaviour Bodyguard.Policy

  alias Lightning.Accounts.User
  alias Lightning.Projects
  alias Lightning.Projects.Project

  @type actions ::
          :delete
          | :read
          | :index
          | :edit
  # Users with admin level access to a project can access project settings with read/write rights
  @spec authorize(actions(), Lightning.Accounts.User.t(), any) :: boolean
  def authorize(:edit, %User{} = user, %Project{} = project) do
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
