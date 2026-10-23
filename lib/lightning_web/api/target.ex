defmodule LightningWeb.API.Target do
  @moduledoc """
  Resolves the target an API action works on in a project, and asks the policy
  whether the caller may act on it, in the order of error-format spec §4.

  The policy is asked only after the target is looked up, so a missing project
  or target is 404 (row 3) even to a member the policy would refuse 403 (row 4).
  A caller with no standing hears the policy's `:no_standing`, also
  404. The token's grant (row 2) has to be refused before any lookup, so an
  action using this module checks it first with
  `LightningWeb.Plugs.AuthorizeAction`. Every refusal is one
  `LightningWeb.API.FallbackController` answers.
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
