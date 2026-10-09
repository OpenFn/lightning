defmodule Lightning.Policies.Provisioning do
  @moduledoc """
  The Bodyguard Policy module for the provisioning API.

  Two kinds of caller reach this: a person with an API token, and a
  `%ProjectRepoConnection{}` — a GitHub connection pushing a project definition
  back to us. Both resolve through `Lightning.Projects.Scope`, so both are
  refused on a project scheduled for deletion. A person is additionally held to
  the project's MFA requirement; a repo connection has no MFA concept, and
  `Scope` says so for it.

  The repo-connection clauses previously compared
  `repo_connection.project_id == project.id`, which is trivially true for the
  project the connection belongs to and asks nothing about the project's state —
  so a push could re-enable the triggers that shutting the project down had
  disabled.

  Only a superuser or a service account can create a project, through
  `:create_project`; provisioning a project that does not exist yet asks the
  same. Owners and admins can update an existing one.
  """
  @behaviour Bodyguard.Policy

  alias Lightning.Accounts.User
  alias Lightning.Policies.Permissions
  alias Lightning.Projects.Project
  alias Lightning.Projects.Scope
  alias Lightning.ServiceAccount
  alias Lightning.VersionControl.ProjectRepoConnection

  @type actions :: :create_project | :provision_project | :describe_project

  @spec authorize(actions(), Scope.actor(), Project.t() | nil) ::
          boolean() | {:error, :forbidden}

  def authorize(:create_project, %User{role: :superuser}, _), do: true

  # The route already held the token to its projects scope.
  def authorize(:create_project, %ServiceAccount{}, _), do: true

  def authorize(:create_project, _, _), do: {:error, :forbidden}

  # STAYS FIRST. A project that does not exist yet cannot be scheduled for
  # deletion, and has no members to consult. Reordering this below the clauses
  # that resolve a Scope breaks project creation through the API.
  def authorize(:provision_project, %User{} = user, %Project{id: nil}) do
    authorize(:create_project, user, nil)
  end

  def authorize(:provision_project, %User{} = user, %Project{} = project) do
    case Scope.fetch(user, project) do
      {:ok, %Scope{role: role, mfa_satisfied?: true}}
      when role in [:owner, :admin] ->
        true

      _ ->
        {:error, :forbidden}
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
