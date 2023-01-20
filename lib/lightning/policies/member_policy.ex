defmodule Lightning.Policies.MemberPolicy do
  @behaviour Bodyguard.Policy

  alias Lightning.Projects
  alias Lightning.Projects.Project
  alias Lightning.Accounts.User

  # Project members can list jobs for a project
  def authorize(:edit_jobs, %User{} = user, %Project{} = project) do
    Projects.get_project_user_role(user, project) in [:admin, :editor, :owner]
  end
end
