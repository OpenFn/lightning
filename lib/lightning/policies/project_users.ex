defmodule Lightning.Policies.ProjectUsers do
  @moduledoc """
  The Bodyguard Policy module for projects members roles.
  """
  @behaviour Bodyguard.Policy

  alias Lightning.Projects
  alias Lightning.Projects.{ProjectUser, Project}
  alias Lightning.Accounts.User

  @type actions ::
          :run_job
          | :edit_job
          | :rerun_job
          | :create_job
          | :access_project
          | :delete_project
          | :delete_workflow
          | :create_workflow
          | :edit_project_name
          | :edit_digest_alerts
          | :edit_failure_alerts
          | :edit_project_description
          | :provision_project
          | :create_webhook_auth_method
          | :edit_webhook_auth_method

  @doc """
  authorize/3 takes an action, a user, and a project. It checks the user's role
  for this project and returns `true` if the user can perform the action in
  that project and `false` if they cannot.

  Note that permissions are grouped by action, rather than by user role.

  We deny by default, so if a user's role is not added to the allow roles list
  for a particular action they are denied.
  """
  @spec authorize(
          actions(),
          Lightning.Accounts.User.t(),
          Lightning.Projects.Project.t() | nil
        ) :: boolean
  def authorize(:access_project, %User{}, nil), do: false

  def authorize(:access_project, %User{} = user, %Project{} = project),
    do:
      is_nil(project.scheduled_deletion) and
        Projects.is_member_of?(project, user)

  def authorize(:delete_project, %User{} = user, %Project{} = project),
    do: Projects.get_project_user_role(user, project) == :owner

  def authorize(
        action,
        %User{id: id} = _user,
        %ProjectUser{user_id: user_id} = _project
      )
      when action in [:edit_digest_alerts, :edit_failure_alerts],
      do: id == user_id

  def authorize(action, %User{} = user, %Project{} = project)
      when action in [
             :edit_project_name,
             :edit_project_description
           ],
      do: Projects.get_project_user_role(user, project) in [:owner, :admin]

  def authorize(action, %User{} = user, %Project{} = project) do
    project_user = Projects.get_project_user(project, user)
    authorize(action, user, project_user)
  end

  def authorize(action, %User{}, %ProjectUser{} = project_user)
      when action in [
             :create_workflow,
             :edit_job,
             :create_job,
             :delete_workflow,
             :run_job,
             :rerun_job,
             :provision_project,
             :create_webhook_auth_method,
             :edit_webhook_auth_method
           ],
      do: project_user.role in [:owner, :admin, :editor]
end
