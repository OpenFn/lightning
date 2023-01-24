defmodule Lightning.Policies.MemberPolicy do
  @moduledoc """
  The Bodyguard Policy module for projects members roles.
  """
  @behaviour Bodyguard.Policy

  alias Lightning.Projects
  alias Lightning.Projects.Project
  alias Lightning.Accounts.User

  # Project members can edit jobs only if they have :admin, :editor, or :owner role
  def authorize(:edit_jobs, %User{} = user, %Project{} = project) do
    Projects.get_project_user_role(user, project) in [:admin, :editor, :owner]
  end
end
