defmodule Lightning.Policies.ProjectDeletion do
  @moduledoc """
  Who may schedule a project for deletion, or cancel its deletion, when the
  project is named by id whether or not it is a sandbox.

    * A workspace root: its owner, as `:delete_project` in
      `Lightning.Policies.ProjectUsers` decides.
    * A sandbox: its owners and admins, and the owners and admins of the
      project at the top of its tree, as `:delete_sandbox` in
      `Lightning.Policies.Sandboxes` decides for a `%User{}`.

  The service account holds every role, so it may do both to any project.

  `:cancel_project_deletion` decides as `:delete_project` would if the project
  weren't scheduled, since its subject is scheduled by definition. It is the
  one project action a scheduled project doesn't refuse.

  Both need the `projects:write` grant.
  """
  @behaviour Bodyguard.Policy

  alias Lightning.Policies.Decision
  alias Lightning.Policies.Permissions
  alias Lightning.Projects
  alias Lightning.Projects.Project
  alias Lightning.Scope

  @type actions :: :delete_project | :cancel_project_deletion

  @grant "projects:write"

  @spec authorize(actions(), Scope.t() | Scope.actor(), Scope.subject()) ::
          Decision.answer()
  def authorize(:delete_project, %Scope{} = scope, subject),
    do: decide(scope, subject)

  def authorize(:cancel_project_deletion, %Scope{} = scope, subject),
    do: decide(%{scope | scheduled_for_deletion?: false}, subject)

  def authorize(_action, %Scope{}, _subject), do: false

  def authorize(action, actor, subject),
    do: Permissions.for_actor(actor, subject, &authorize(action, &1, subject))

  defp decide(scope, subject) do
    case Decision.project(scope, subject, @grant, own_rule(scope)) do
      refused when refused in [false, {:error, :no_standing}] ->
        if sandbox?(scope), do: root_cascade(scope, refused), else: refused

      answer ->
        answer
    end
  end

  defp own_rule(%Scope{project: %Project{parent_id: nil}} = scope),
    do: Scope.holds_role?(scope, [:owner])

  defp own_rule(%Scope{project: %Project{}} = scope),
    do: Scope.holds_role?(scope, [:owner, :admin])

  defp own_rule(%Scope{project: nil}), do: false

  defp sandbox?(%Scope{project: project}), do: Project.sandbox?(project)

  # An owner or admin of the root counts as an admin of the sandbox, decided on
  # the root's own facts, MFA and deletion included. Only after the sandbox's
  # own answer refused, so the sandbox's facts were judged first; and the
  # sandbox still has to be operable, so a scheduled one answers as a
  # scheduled project does.
  defp root_cascade(scope, refused) do
    root = Projects.root_of(scope.project)

    with {:ok, root_scope} <- Scope.fetch(scope, root),
         true <-
           Decision.project(
             root_scope,
             root,
             @grant,
             Scope.holds_role?(root_scope, [:owner, :admin])
           ) do
      if scope.scheduled_for_deletion?,
        do: {:error, :scheduled_for_deletion},
        else: true
    else
      _refused -> refused
    end
  end
end
