defmodule Lightning.Projects.Policy do
  @moduledoc """
  The Bodyguard Policy module.
  """
  @behaviour Bodyguard.Policy

  alias Lightning.Accounts.User
  alias Lightning.Projects

  # Project members can read a project
  def authorize(action, user, project) when action in [:read, :index] do
    Projects.is_member_of?(project, user)
  end

  # Super users can do anything
  def authorize(_action, %User{role: :superuser}, _params), do: true

  # Default deny
  def authorize(_, _user, _project), do: false
end
