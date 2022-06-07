defmodule Lightning.Jobs.Policy do
  @moduledoc """
  The Bodyguard Policy module.
  """
  @behaviour Bodyguard.Policy

  alias Lightning.Projects

  # Project members can list jobs for a project
  def authorize(:list, user, project) do
    Projects.is_member_of?(project, user)
  end

  # Default deny
  def authorize(_, _user, _project), do: false
end
