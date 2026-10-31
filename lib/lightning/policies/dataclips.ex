defmodule Lightning.Policies.Dataclips do
  @moduledoc """
  The Bodyguard Policy module for dataclips actions.

  A dataclip belongs to a project, and viewing one is exactly project access —
  so this delegates rather than re-deciding. The previous implementation built a
  `%Project{}` from the dataclip's `project_id` and asked whether the user was a
  member of it, which could not see `scheduled_deletion` and so served bodies
  from projects that had been shut down.
  """
  @behaviour Bodyguard.Policy

  alias Lightning.Accounts.User
  alias Lightning.Invocation.Dataclip
  alias Lightning.Policies.Permissions

  @type actions :: :view_dataclip

  @spec authorize(actions(), User.t(), Dataclip.t()) :: boolean()
  def authorize(:view_dataclip, %User{} = user, %Dataclip{} = dataclip) do
    Permissions.can?(:project_users, :access_project, user, dataclip)
  end
end
