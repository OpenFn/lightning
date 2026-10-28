defmodule LightningWeb.API.Target do
  @moduledoc """
  Resolves the project an API action works on, and the record inside it, then
  asks the policy whether the caller may act on it. It takes the
  `Lightning.Scope` that `LightningWeb.Plugs.AuthorizeAction` assigned, and
  every refusal it returns is one `LightningWeb.API.FallbackController`
  answers.

  The policy is asked only after the lookup, so a missing project or record is
  404 even to a member the policy would refuse with 403. A caller with no
  standing on the project hears `:no_standing` from `Lightning.Scope` or the
  policy, which is also 404. The token grant has to be refused before any
  lookup, which is why `AuthorizeAction` checks it first.
  """
  alias Lightning.Policies.Permissions
  alias Lightning.Projects.Project
  alias Lightning.Scope

  @type permission :: {policy :: atom(), action :: atom()}

  @doc """
  The project `subject` identifies, once the caller may apply the permission to
  it.

      Target.project(conn.assigns.scope, project_id, {:project_users, :access_project})
  """
  @spec project(Scope.t() | Scope.actor(), Scope.subject(), permission()) ::
          {:ok, Project.t()} | {:error, term()}
  def project(scope, subject, permission),
    do: in_project(scope, subject, permission, &{:ok, &1})

  @doc """
  The project `id` names, as `project/3` answers it, or a new, unsaved
  `%Project{}` when no project has that id, or `id` is nil, and the caller may
  create projects.

  An id taken by a project the caller has no standing on is still 404, not a new
  project (plan D14).
  """
  @spec project_or_new(
          Scope.t() | Scope.actor(),
          Ecto.UUID.t() | nil,
          permission()
        ) :: {:ok, Project.t()} | {:error, term()}
  def project_or_new(scope, nil, _permission), do: new_project(scope)

  def project_or_new(scope, id, permission) do
    case project(scope, id, permission) do
      {:error, :no_such_project} -> new_project(scope)
      found_or_refused -> found_or_refused
    end
  end

  defp new_project(scope) do
    with :ok <- Permissions.permit(:provisioning, :create_project, scope, nil),
         do: {:ok, %Project{}}
  end

  @doc """
  What `lookup` finds in the project `subject` identifies, once the caller may
  apply the permission to that project. `lookup` is given the project and
  answers `{:ok, target}`, or a refusal such as `{:error, :not_found}`.

      Target.in_project(scope, project_id, {:project_users, :edit_workflow},
        &fetch_workflow(id, &1)
      )
  """
  @spec in_project(
          Scope.t() | Scope.actor(),
          Scope.subject(),
          permission(),
          (Project.t() -> {:ok, target} | {:error, term()})
        ) :: {:ok, target} | {:error, term()}
        when target: term()
  def in_project(scope, subject, {policy, action}, lookup) do
    with {:ok, scope} <- Scope.fetch(scope, subject),
         {:ok, target} <- lookup.(scope.project),
         :ok <- Permissions.permit(policy, action, scope, scope.project),
         do: {:ok, target}
  end
end
