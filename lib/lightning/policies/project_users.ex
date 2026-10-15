defmodule Lightning.Policies.ProjectUsers do
  @moduledoc """
  The Bodyguard Policy module for project members' roles.

  Two steps, deliberately separate.

  `Lightning.Scope` establishes the **facts**: which project, and what
  standing this actor has in it, including whether the project is scheduled
  for deletion.

  `authorize/3` on a `%Scope{}` makes the **judgement**, in the order
  `Lightning.Policies.Decision` sets. It never mentions
  `Project.scheduled_deletion` or `Project.requires_mfa`. Both reach it as
  facts on the scope.

  Adding an action means adding an atom to `@admin_actions` or
  `@editor_actions`. It inherits the guards; there is nothing to remember.

  We deny by default: an action in none of the lists is refused.
  """
  @behaviour Bodyguard.Policy

  alias Lightning.Policies.Decision
  alias Lightning.Policies.Permissions
  alias Lightning.Projects.ProjectUser
  alias Lightning.Scope

  @admin_actions [
    :write_webhook_auth_method,
    :write_github_connection,
    :edit_project,
    :edit_data_retention,
    :add_project_user,
    :remove_project_user,
    :edit_run_settings
  ]

  @editor_actions [
    :create_workflow,
    :edit_workflow,
    :delete_workflow,
    :run_workflow,
    :create_project_credential,
    :initiate_github_sync,
    :create_channel,
    :delete_channel,
    :update_channel
  ]

  @self_actions [:edit_digest_alerts, :edit_failure_alerts]

  @other_actions [
    :access_project,
    :list_project_credentials,
    :delete_project,
    :publish_template
  ]

  @owner_roles [:owner]
  @admin_roles [:owner, :admin]
  @editor_roles [:owner, :admin, :editor]

  @type actions ::
          :access_project
          | :list_project_credentials
          | :delete_project
          | :publish_template
          | :run_workflow
          | :edit_workflow
          | :delete_workflow
          | :create_workflow
          | :create_project_credential
          | :initiate_github_sync
          | :create_channel
          | :delete_channel
          | :update_channel
          | :edit_project
          | :edit_data_retention
          | :edit_run_settings
          | :add_project_user
          | :remove_project_user
          | :write_webhook_auth_method
          | :write_github_connection
          | :edit_digest_alerts
          | :edit_failure_alerts

  @doc """
  Every action this policy decides. Read by the recurrence test, so a new action
  is covered the day it is added rather than the day someone remembers.
  """
  @spec actions() :: [actions()]
  def actions,
    do: @admin_actions ++ @editor_actions ++ @self_actions ++ @other_actions

  @doc """
  Whether the caller may perform `action`, where the subject is anything that
  identifies a project — see `t:Lightning.Scope.subject/0`.

  Given a `%Scope{}`, the subject must be the scope's own project or one of
  its membership rows.
  """
  @spec authorize(actions(), Scope.t() | Scope.actor(), Scope.subject()) ::
          Decision.answer()
  def authorize(action, %Scope{} = scope, subject),
    do:
      Decision.project(
        scope,
        subject,
        grant(action),
        judge(action, scope, subject)
      )

  def authorize(action, actor, subject),
    do: Permissions.for_actor(actor, subject, &authorize(action, &1, subject))

  @doc """
  Decide an action against an already-resolved `%Scope{}`, as a boolean.

  Public so a caller needing several answers about one project resolves once
  rather than once per question. It is `false` when the scope lacks the
  action's grant, and on a project scheduled for deletion.
  """
  @spec permitted?(actions(), Scope.t()) :: boolean()
  def permitted?(action, %Scope{} = scope),
    do: authorize(action, scope, scope.project) == true

  @doc """
  Whether this actor would have standing on the project if not for the
  project's MFA requirement.

  Lets a caller distinguish "no access at all" from "access except MFA" —
  `LightningWeb.Hooks` sends the first to not-found and the second to
  `/mfa_required` — without duplicating what counts as standing. It cannot ask
  `permitted?(:access_project, ...)` for that, since that answers `false` for
  both cases. A project scheduled for deletion is not-found for everyone, so
  it is never "blocked by MFA".
  """
  @spec blocked_by_mfa?(Scope.t()) :: boolean()
  def blocked_by_mfa?(%Scope{mfa_satisfied?: mfa_satisfied?} = scope),
    do:
      Scope.has_standing?(scope) and not mfa_satisfied? and
        not scope.scheduled_for_deletion?

  defp grant(action)
       when action in [:create_project_credential, :list_project_credentials],
       do: "credentials:write"

  defp grant(_action), do: "projects:write"

  # These act on a specific membership row, not on project standing. The alert
  # handlers in `ProjectLive.Settings` pass a client-supplied "project_user_id",
  # so dropping the comparison with the caller's own row is a privilege
  # escalation. Two tests in project_live_test.exs pin it.
  defp judge(action, %Scope{project_user: own_row}, %ProjectUser{id: id})
       when action in @self_actions,
       do: not is_nil(own_row) and own_row.id == id

  defp judge(action, scope, _subject), do: judge(action, scope)

  defp judge(action, scope)
       when action in [:access_project, :list_project_credentials],
       do: Scope.has_standing?(scope)

  defp judge(:delete_project, scope), do: Scope.holds_role?(scope, @owner_roles)

  # Support-staff-only: a project owner cannot publish, and staff can publish
  # without holding a membership row. Needs both support fields separately, so
  # do not fold it into @editor_actions — that drops the support_user
  # requirement silently.
  defp judge(:publish_template, %Scope{support_user?: true} = scope),
    do: not is_nil(scope.role) or scope.support?

  defp judge(:publish_template, _scope), do: false

  # Reached only when the subject wasn't a %ProjectUser{} — Scope resolves the
  # caller's own standing, so there is no "which row" ambiguity here. An
  # operator has no row, so gets nothing.
  defp judge(action, scope) when action in @self_actions,
    do: not is_nil(scope.role)

  # A support user with no membership row holds no admin action.
  defp judge(action, scope) when action in @admin_actions,
    do: Scope.holds_role?(scope, @admin_roles)

  # An explicit row wins; support access only fills in for someone with no row
  # at all. So adding a support user as a viewer gives them viewer permissions
  # rather than their account flag overriding it. Under the opposite rule,
  # "this person is read-only here" could not be expressed at all.
  defp judge(action, scope) when action in @editor_actions,
    do:
      Scope.holds_role?(scope, @editor_roles) or
        (is_nil(scope.role) and scope.support?)

  defp judge(_action, _scope), do: false
end
