defmodule Lightning.Policies.Workflows do
  @moduledoc """
  The Bodyguard Policy module for Workflows API.
  """
  @behaviour Bodyguard.Policy

  alias Lightning.Accounts.User
  alias Lightning.Policies.Decision
  alias Lightning.Policies.ProjectUsers
  alias Lightning.Projects.Project
  alias Lightning.Run
  alias Lightning.Scope

  @type actions :: :access_write | :access_read
  @spec authorize(actions(), User.t() | Run.t(), Project.t()) ::
          :ok | {:error, :unauthorized}
  def authorize(access, %User{} = user, project)
      when access in [:access_write, :access_read] do
    Lightning.Policies.Permissions.can(
      Lightning.Policies.ProjectUsers,
      :access_project,
      user,
      project
    )
  end

  def authorize(access, %Run{} = run, project)
      when access in [:access_write, :access_read] do
    Lightning.Runs.get_project_id_for_run(run) == project.id
  end

  # The API's actions on a workflow's lifecycle and history, open to a person
  # on either of their tokens, a personal access token or a session token, and
  # to nothing else (`Decision.person/2`): the service account and repo
  # connections are refused 403 before anything is looked up. Within that, the
  # rule is `Lightning.Policies.ProjectUsers`'s, so a project's roles, MFA
  # requirement and scheduled deletion apply as they do in the app.
  #
  #   * `:delete_workflow` - owners, admins and editors. Never the service
  #     account, though it may create and replace workflows: a deleted
  #     workflow can't be restored, and the service account may only make a
  #     deletion that waits out a retention period and can be cancelled, as a
  #     project's (`Lightning.Policies.ProjectDeletion`) or a credential's
  #     (`:schedule_credential_deletion`) does.
  #   * `:read_workflow_history` - any member, for snapshots and versions.
  #   * `:publish_template` - support users who are members, or whose project
  #     allows support access.
  #   * `:list_templates` - anyone; templates are published instance-wide.
  @type api_actions ::
          :delete_workflow
          | :read_workflow_history
          | :publish_template
          | :list_templates

  @spec authorize(api_actions(), Scope.t(), term()) :: Decision.answer()
  def authorize(action, %Scope{} = scope, subject)
      when action in [:delete_workflow, :publish_template],
      do: Decision.person(scope, ProjectUsers.authorize(action, scope, subject))

  def authorize(:read_workflow_history, %Scope{} = scope, subject),
    do:
      Decision.person(
        scope,
        ProjectUsers.authorize(:access_project, scope, subject)
      )

  def authorize(:list_templates, %Scope{} = scope, subject),
    do:
      Decision.person(
        scope,
        Decision.instance(scope, subject, "projects:write", true)
      )
end
