defmodule Lightning.Policies.Dataclips do
  @moduledoc """
  The Bodyguard Policy module for dataclips actions.

  A dataclip belongs to a project, and viewing one is exactly project access —
  so this delegates rather than re-deciding. The previous implementation built a
  `%Project{}` from the dataclip's `project_id` and asked whether the user was a
  member of it, which could not see `scheduled_deletion` and so served bodies
  from projects that had been shut down.

  On a `%Scope{}`, viewing is `:access_project` and renaming is
  `:edit_workflow` in `Lightning.Policies.ProjectUsers`, as the app decides
  them, and both are for people only: a dataclip's body is data that passed
  through a run, which no token grant of the service account covers.
  """
  @behaviour Bodyguard.Policy

  alias Lightning.Accounts.User
  alias Lightning.Invocation.Dataclip
  alias Lightning.Policies.Decision
  alias Lightning.Policies.Permissions
  alias Lightning.Policies.ProjectUsers
  alias Lightning.Scope

  @type actions :: :view_dataclip | :edit_dataclip

  @spec authorize(actions(), User.t() | Scope.t(), Dataclip.t() | term()) ::
          Decision.answer()
  def authorize(action, %Scope{} = scope, subject)
      when action in [:view_dataclip, :edit_dataclip],
      do:
        Decision.person(
          scope,
          ProjectUsers.authorize(project_action(action), scope, subject)
        )

  def authorize(:view_dataclip, %User{} = user, %Dataclip{} = dataclip) do
    Permissions.can?(:project_users, :access_project, user, dataclip)
  end

  defp project_action(:view_dataclip), do: :access_project
  defp project_action(:edit_dataclip), do: :edit_workflow
end
