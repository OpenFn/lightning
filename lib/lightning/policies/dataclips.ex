defmodule Lightning.Policies.Dataclips do
  @moduledoc """
  The Bodyguard Policy module for dataclips actions
  """
  @behaviour Bodyguard.Policy

  alias Lightning.Accounts.User
  alias Lightning.Invocation.Dataclip
  alias Lightning.Projects

  @type actions :: :view_dataclip

  @spec authorize(actions(), User.t(), Dataclip.t()) :: boolean()
  def authorize(:view_dataclip, %User{} = user, %Dataclip{project_id: project_id}) do
    project = Projects.get_project!(project_id)
    Projects.member_of?(project, user)
  end
end
