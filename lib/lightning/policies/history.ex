defmodule Lightning.Policies.History do
  @moduledoc """
  The Bodyguard Policy module for what the API does with a project's history:
  starting, retrying and cancelling work orders and runs, reading a run's
  steps, and exporting history.

  Each action is open to a person on either of their tokens, a personal access
  token or a session token, and to nothing else (`Decision.person/2`): the
  service account and repo connections are refused 403 before anything is
  looked up. Within that, the rule is `Lightning.Policies.ProjectUsers`'s, so
  a project's roles, MFA requirement and scheduled deletion apply as they do
  on the History page.

    * `:run_workflow` - owners, admins and editors, as the History page's Run,
      retry, cancel and export buttons need.
    * `:read_history` - any member, viewers included.
  """
  @behaviour Bodyguard.Policy

  alias Lightning.Policies.Decision
  alias Lightning.Policies.ProjectUsers
  alias Lightning.Scope

  @type actions :: :run_workflow | :read_history

  @spec authorize(actions(), Scope.t(), term()) :: Decision.answer()
  def authorize(:run_workflow, %Scope{} = scope, subject),
    do:
      Decision.person(
        scope,
        ProjectUsers.authorize(:run_workflow, scope, subject)
      )

  def authorize(:read_history, %Scope{} = scope, subject),
    do:
      Decision.person(
        scope,
        ProjectUsers.authorize(:access_project, scope, subject)
      )
end
