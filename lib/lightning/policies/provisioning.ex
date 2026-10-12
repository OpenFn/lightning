defmodule Lightning.Policies.Provisioning do
  @moduledoc """
  The Bodyguard Policy module for the provisioning API.

  Two kinds of caller reach this: a person with an API token, and a
  `%ProjectRepoConnection{}` — a GitHub connection pushing a project definition
  back to us. Both resolve through `Lightning.Scope`. A person is additionally
  held to the project's MFA requirement; a repo connection has no MFA concept,
  and `Scope` says so for it. A caller who would otherwise be allowed on a
  project scheduled for deletion hears `{:error, :scheduled_for_deletion}`,
  as on every other API.

  Only a superuser or an operator can create a project, through
  `:create_project`, and a client token also needs `projects:write`;
  provisioning a project that does not exist yet asks the same. Owners and
  admins can update an existing one. `:provision_project` and
  `:describe_project` need no grant: a repo connection holds none and must
  keep provisioning.
  """
  @behaviour Bodyguard.Policy

  alias Lightning.Policies.Decision
  alias Lightning.Policies.ProjectUsers
  alias Lightning.Projects.Project
  alias Lightning.Scope
  alias Lightning.VersionControl.ProjectRepoConnection

  @type actions :: :create_project | :provision_project | :describe_project

  @spec authorize(actions(), Scope.t() | Scope.actor(), Project.t() | nil) ::
          boolean()
          | {:error, :forbidden | :insufficient_scope | :scheduled_for_deletion}

  # Refusals are `{:error, :forbidden}` rather than `false`, so `/api/provision`
  # answers 403, not 401.
  def authorize(:create_project, %Scope{} = scope, subject) do
    Decision.instance(
      scope,
      subject,
      "projects:write",
      scope.instance_role in [:superuser, :operator]
    ) || {:error, :forbidden}
  end

  def authorize(:create_project, actor, _subject),
    do: authorize(:create_project, Scope.new(actor), nil)

  # STAYS ABOVE the clauses that resolve a Scope. A project that does not exist
  # yet cannot be scheduled for deletion, and has no members to consult.
  def authorize(:provision_project, actor_or_scope, %Project{id: nil}),
    do: authorize(:create_project, actor_or_scope, nil)

  # No grant, so not `Decision.project/4`: a repo connection holds none. The
  # order is the same, so only an allowed caller learns of the deletion.
  def authorize(action, %Scope{} = scope, %Project{} = project)
      when action in [:provision_project, :describe_project] do
    cond do
      not Scope.describes?(scope, project) -> {:error, :forbidden}
      not judge(action, scope) -> {:error, :forbidden}
      scope.scheduled_for_deletion? -> {:error, :scheduled_for_deletion}
      true -> true
    end
  end

  def authorize(action, actor, %Project{} = project)
      when action in [:provision_project, :describe_project] do
    case Scope.fetch(actor, project) do
      {:ok, scope} -> authorize(action, scope, project)
      {:error, _reason} -> {:error, :forbidden}
    end
  end

  def authorize(_, _, _), do: false

  # A repo connection's standing is the project it belongs to, which
  # `describes?/2` has already checked.
  defp judge(_action, %Scope{actor: %ProjectRepoConnection{}}), do: true

  defp judge(:provision_project, scope),
    do: scope.mfa_satisfied? and Scope.holds_role?(scope, [:owner, :admin])

  # Delegated rather than copied, so it cannot drift from `:access_project`.
  # `:scheduled_for_deletion` is its answer to a caller it otherwise allows.
  defp judge(:describe_project, scope),
    do:
      ProjectUsers.authorize(:access_project, scope, scope.project) in [
        true,
        {:error, :scheduled_for_deletion}
      ]
end
