defmodule Lightning.Policies.ProjectUsers do
  @moduledoc """
  The Bodyguard Policy module for projects members roles.
  """
  @behaviour Bodyguard.Policy

  alias Lightning.Projects
  alias Lightning.Projects.Project
  alias Lightning.Accounts.User

  @type actions ::
          :create_workflow
          | :edit_job
          | :create_job
          | :delete_job
          | :run_job
          | :rerun_job
          | :view_last_job_inputs
          | :view_workorder_input
          | :view_workorder_run
          | :view_workorder_history
          | :view_project_name
          | :view_project_description
          | :view_project_credentials
          | :view_project_collaborators

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
          Lightning.Projects.Project.t()
        ) :: boolean
  def authorize(action, %User{} = user, %Project{} = project)
      when action in [
             :create_workflow,
             :edit_job,
             :create_job,
             :delete_job,
             :run_job,
             :rerun_job
           ] do
    Projects.get_project_user_role(user, project) in [:owner, :admin, :editor]
  end

  def authorize(action, %User{} = user, %Project{} = project)
      when action in [
             :view_last_job_inputs,
             :view_workorder_input,
             :view_workorder_run,
             :view_workorder_history,
             :view_project_name,
             :view_project_description,
             :view_project_credentials,
             :view_project_collaborators
           ],
      do: true
end
