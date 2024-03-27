defmodule Lightning.Policies.Provisioning do
  @moduledoc """
  The Bodyguard Policy module for users roles.
  """
  @behaviour Bodyguard.Policy

  alias Lightning.Accounts.User
  alias Lightning.Projects
  alias Lightning.Projects.Project
  alias Lightning.VersionControl.ProjectRepoConnection

  @type actions :: :provision_project | :describe_project

  @doc """
  authorize/3 takes an action, a user or a project repo connection, and a project. It checks the user's role
  for this project and returns `true` if the user can perform the action and
  false if they cannot.

  Note that permissions are grouped by action.

  We deny by default, so if a user's role is not added to the allow roles list
  for a particular action they are denied.

  Only a superuser can provision a new project.

  Owners and admins can update existing projects.
  """
  @spec authorize(actions(), Lightning.Accounts.User.t(), Project.t()) :: boolean
  def authorize(:provision_project, %User{role: role}, %Project{id: nil}) do
    role in [:superuser] or {:error, :forbidden}
  end

  def authorize(:provision_project, %User{} = user, %Project{} = project) do
    Projects.get_project_user_role(user, project) in [
      :owner,
      :admin
    ] or {:error, :forbidden}
  end

  def authorize(
        :provision_project,
        %ProjectRepoConnection{} = repo_connection,
        %Project{} = project
      ) do
    repo_connection.project_id == project.id or {:error, :forbidden}
  end

  def authorize(:describe_project, %User{} = user, %Project{} = project) do
    Projects.get_project_user_role(user, project) in [
      :owner,
      :admin,
      :editor,
      :viewer
    ] or {:error, :forbidden}
  end

  def authorize(
        :describe_project,
        %ProjectRepoConnection{} = repo_connection,
        %Project{} = project
      ) do
    repo_connection.project_id == project.id or {:error, :forbidden}
  end

  def authorize(_, _, _), do: false
end
