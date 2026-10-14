defmodule Lightning.Policies.Provisioning do
  @moduledoc """
  The Bodyguard Policy module for the provisioning API.

  Three kinds of caller reach this: a person with an API token, a service
  account creating a project, and a `%ProjectRepoConnection{}` (a GitHub
  connection pushing a project definition back to us). All resolve through
  `Lightning.Scope`. A person is additionally held to the project's MFA
  requirement; a repo connection has no MFA concept, and `Scope` says so for
  it. A caller who would otherwise be allowed on a project scheduled for
  deletion hears `{:error, :scheduled_for_deletion}`.

  Only a superuser or an operator holding `projects:write` can create a
  project, whether through `:create_project` or by provisioning one that does
  not exist yet. Owners and admins can update an existing one.
  `:provision_project` and `:describe_project` on an existing project need
  `projects:provision`, the one grant a repo connection holds.
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

  # `false` becomes `{:error, :forbidden}`, so `/api/provision` answers 403, not
  # 401.
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

  # Stays above the clauses that resolve a Scope, which refuse a project that
  # does not exist yet and so would block creation.
  def authorize(:provision_project, actor_or_scope, %Project{id: nil}),
    do: authorize(:create_project, actor_or_scope, nil)

  def authorize(action, %Scope{} = scope, %Project{} = project)
      when action in [:provision_project, :describe_project] do
    Decision.project(scope, project, "projects:provision", judge(action, scope)) ||
      {:error, :forbidden}
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
    do: Scope.holds_role?(scope, [:owner, :admin])

  # Delegated rather than copied, so it cannot drift from `:access_project`.
  # It answers `:scheduled_for_deletion` only to a caller it would allow.
  defp judge(:describe_project, scope),
    do:
      ProjectUsers.authorize(:access_project, scope, scope.project) in [
        true,
        {:error, :scheduled_for_deletion}
      ]
end
