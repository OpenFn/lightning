defmodule Lightning.Policies.ProjectUsers do
  @moduledoc """
  The Bodyguard Policy module for project members' roles.

  Two steps, deliberately separate.

  `Lightning.Projects.Scope` establishes the **facts**: which project, and what
  standing this actor has in it. It refuses outright for a project that does not
  exist or is scheduled for deletion, so nothing downstream can be handed a
  standing in a wound-down project.

  `permitted?/2` makes the **judgement**: given that standing, is this action
  allowed. It decides on `role` alone and never mentions
  `Project.scheduled_deletion` — there is no shut-down project left for it to
  see.

  Adding an action means adding an atom to `@admin_actions` or
  `@editor_actions`. It inherits the guard; there is nothing to remember.

  We deny by default: an action in none of the lists is refused.
  """
  @behaviour Bodyguard.Policy

  alias Lightning.Accounts.User
  alias Lightning.Projects.ProjectUser
  alias Lightning.Projects.Scope

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

  @other_actions [:access_project, :delete_project, :publish_template]

  @type actions ::
          :access_project
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
  Whether `user` may perform `action`, where the subject is anything that
  identifies a project — see `t:Lightning.Projects.Scope.subject/0`.
  """
  @spec authorize(actions(), User.t(), Scope.subject()) :: boolean()

  # These act on a specific membership row, not on project standing. The alert
  # handlers in `ProjectLive.Settings` pass a client-supplied "project_user_id",
  # so dropping the `id == user_id` comparison is a privilege escalation —
  # pinned by two tests in project_live_test.exs.
  def authorize(
        action,
        %User{id: id} = user,
        %ProjectUser{user_id: user_id} = project_user
      )
      when action in @self_actions do
    id == user_id and match?({:ok, _}, Scope.fetch(user, project_user))
  end

  def authorize(action, %User{} = user, subject) do
    case Scope.fetch(user, subject) do
      {:ok, scope} ->
        permitted?(action, scope)

      # Bodyguard's contract is boolean, so the reason stops here. A caller
      # wanting the distinction resolves Scope itself.
      {:error, _reason} ->
        false
    end
  end

  @doc """
  Decide an action against an already-resolved `%Scope{}`.

  Public so a caller needing several answers about one project resolves once
  rather than once per question.
  """
  @spec permitted?(actions(), Scope.t()) :: boolean()
  def permitted?(:access_project, %Scope{role: role, support?: support?}),
    do: not is_nil(role) or support?

  def permitted?(:delete_project, %Scope{role: role}), do: role == :owner

  # Support-staff-only: a project owner cannot publish, and staff can publish
  # without holding a membership row. Needs both support fields separately, so
  # do not fold it into @editor_actions — that drops the support_user
  # requirement silently.
  def permitted?(:publish_template, %Scope{
        support_user?: true,
        role: role,
        support?: support?
      }),
      do: not is_nil(role) or support?

  def permitted?(:publish_template, %Scope{}), do: false

  # Reached only when the subject wasn't a %ProjectUser{} — Scope resolves the
  # caller's own standing, so there is no "which row" ambiguity here.
  def permitted?(action, %Scope{role: role}) when action in @self_actions,
    do: not is_nil(role)

  # Admin actions have never been available to a support user without a
  # membership row. Unchanged here.
  def permitted?(action, %Scope{role: role}) when action in @admin_actions,
    do: role in [:owner, :admin]

  # An explicit row wins; support access only fills in for someone with no row
  # at all. So adding a support user as a viewer gives them viewer permissions
  # rather than their account flag overriding it. Under the opposite rule,
  # "this person is read-only here" could not be expressed at all.
  def permitted?(action, %Scope{role: nil, support?: support?})
      when action in @editor_actions,
      do: support?

  def permitted?(action, %Scope{role: role}) when action in @editor_actions,
    do: role in [:owner, :admin, :editor]

  def permitted?(_action, %Scope{}), do: false
end
