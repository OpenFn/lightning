defmodule Lightning.Policies.Provisioning do
  @moduledoc """
  The Bodyguard Policy module for the provisioning API.

  Two kinds of caller reach this: a person with an API token, and a
  `%ProjectRepoConnection{}` — a GitHub connection pushing a project definition
  back to us. Both resolve through `Lightning.Projects.Scope`, so both are
  refused on a project scheduled for deletion.

  The repo-connection clauses previously compared
  `repo_connection.project_id == project.id`, which is trivially true for the
  project the connection belongs to and asks nothing about the project's state —
  so a push could re-enable the triggers that shutting the project down had
  disabled.

  Only a superuser can provision a project that does not exist yet. Owners and
  admins can update an existing one.
  """
  @behaviour Bodyguard.Policy

  alias Lightning.Accounts.User
  alias Lightning.Policies.Permissions
  alias Lightning.Projects.Project
  alias Lightning.Projects.Scope
  alias Lightning.VersionControl.ProjectRepoConnection

  @type actor :: User.t() | ProjectRepoConnection.t()
  @type actions :: :provision_project | :describe_project

  @spec authorize(actions(), actor(), Project.t()) ::
          boolean() | {:error, :forbidden}

  # STAYS FIRST. A project that does not exist yet cannot be scheduled for
  # deletion, and has no members to consult. Reordering this below the clauses
  # that resolve a Scope breaks project creation through the API.
  def authorize(:provision_project, %User{role: role}, %Project{id: nil}) do
    role in [:superuser] or {:error, :forbidden}
  end

  def authorize(:provision_project, %User{} = user, %Project{} = project) do
    case Scope.fetch(user, project) do
      {:ok, %Scope{role: role}} when role in [:owner, :admin] -> true
      _ -> {:error, :forbidden}
    end
  end

  # Delegated rather than copied, so it cannot drift from `:access_project`.
  def authorize(:describe_project, %User{} = user, %Project{} = project) do
    Permissions.can?(:project_users, :access_project, user, project) or
      {:error, :forbidden}
  end

  # Resolving a Scope at all is the whole check: Scope refuses a project this
  # connection does not belong to, and one scheduled for deletion.
  def authorize(
        action,
        %ProjectRepoConnection{} = repo_connection,
        %Project{} = project
      )
      when action in [:provision_project, :describe_project] do
    match?({:ok, _}, Scope.fetch(repo_connection, project)) or
      {:error, :forbidden}
  end

  def authorize(_, _, _), do: false
end
