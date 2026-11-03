defmodule Lightning.Policies.Provisioning do
  @moduledoc """
  The Bodyguard Policy module for the provisioning API.

  Three kinds of caller reach this: a person with an API token, the service
  account, and a `%ProjectRepoConnection{}` (a GitHub connection pushing a
  project definition back to us). The service account may describe a project
  but is refused `:provision_project` and `:provision_new_project` in the rule,
  whatever its grants. All resolve through `Lightning.Scope`. A person is
  additionally held to the project's MFA requirement; a repo connection has no
  MFA concept, and `Scope` says so for it. A caller who would otherwise be allowed on a project scheduled for
  deletion hears `{:error, :scheduled_for_deletion}`, and one with no standing
  on the project `{:error, :no_standing}`, which reveals nothing about the
  project, not even that it exists.

  Only a superuser or an operator holding `projects:write` can create a
  project (`:create_project`), and only a superuser can create one by
  provisioning (`:provision_new_project`). Owners and admins can update an
  existing one. `:provision_project` and `:describe_project` on an existing
  project need `projects:write` or `projects:provision`, since a write grant
  covers both; `projects:provision` is the one grant a repo connection holds.
  """
  @behaviour Bodyguard.Policy

  alias Lightning.Policies.Decision
  alias Lightning.Policies.ProjectUsers
  alias Lightning.Projects.Project
  alias Lightning.Scope
  alias Lightning.ServiceAccount
  alias Lightning.VersionControl.ProjectRepoConnection

  @type actions ::
          :create_project
          | :provision_new_project
          | :provision_project
          | :describe_project

  @project_grants ["projects:write", "projects:provision"]

  @spec authorize(
          actions(),
          Scope.t(),
          Project.t() | nil | :before_target
        ) ::
          boolean()
          | {:error,
             :forbidden
             | Decision.insufficient_scope()
             | :no_standing
             | :scheduled_for_deletion}

  # `false` becomes `{:error, :forbidden}`, so `/api/provision` answers 403, not
  # 401.
  def authorize(:create_project, %Scope{} = scope, subject) do
    Decision.instance(
      scope,
      subject,
      "projects:write",
      Scope.instance_wide?(scope)
    ) || {:error, :forbidden}
  end

  def authorize(:provision_new_project, %Scope{} = scope, subject) do
    Decision.instance(scope, subject, "projects:write", may_import_new?(scope)) ||
      {:error, :forbidden}
  end

  def authorize(action, %Scope{} = scope, :before_target)
      when action in [:provision_project, :describe_project],
      do: Decision.instance(scope, :before_target, @project_grants, true)

  def authorize(action, %Scope{} = scope, %Project{} = project)
      when action in [:provision_project, :describe_project] do
    case Decision.project(
           scope,
           project,
           @project_grants,
           judge(action, scope)
         ) do
      false -> {:error, :forbidden}
      answer -> answer
    end
  end

  def authorize(_, _, _), do: false

  # A project the service account provisions would get no owner, and the
  # credentials its body links would be skipped, since the provisioner gives
  # both only to a `%User{}`.
  defp may_import_new?(%Scope{actor: %ServiceAccount{}}), do: false
  defp may_import_new?(scope), do: Scope.instance_wide?(scope)

  # A repo connection's standing is the project it belongs to, which
  # `describes?/2` has already checked.
  defp judge(_action, %Scope{actor: %ProjectRepoConnection{}}), do: true

  defp judge(:provision_project, %Scope{actor: %ServiceAccount{}}), do: false

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
