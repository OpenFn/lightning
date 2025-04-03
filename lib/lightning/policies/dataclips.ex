defmodule Lightning.Policies.Dataclips do
  @moduledoc """
  The Bodyguard Policy module for dataclips actions
  """
  @behaviour Bodyguard.Policy

  alias Lightning.Accounts.User
  alias Lightning.Invocation.Dataclip
  alias Lightning.Policies.ProjectUsers
  alias Lightning.Projects
  alias Lightning.Projects.Project

  @type actions :: :view_dataclip

  @spec authorize(actions(), User.t(), Dataclip.t()) :: boolean()
  def authorize(:view_dataclip, %User{} = user, %Dataclip{project_id: project_id}) do
    ProjectUsers.allow_as_support_user?(user, project_id) or
      Projects.member_of?(%Project{id: project_id}, user)
  end
end
