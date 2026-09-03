defmodule Lightning.Projects.Scope do
  @moduledoc """
  What standing does an actor have in a project, right now.

  `fetch/2` establishes facts, not permission: it reports the actor's role, and
  refuses outright for a project that does not exist or is scheduled for
  deletion. Whether that standing is enough for an action is the policy's
  judgement — see `Lightning.Policies.ProjectUsers.permitted?/2`.

      {:ok, %Scope{role: :editor}}
      {:ok, %Scope{role: nil}}                      no membership row
      {:error, :no_such_project}
      {:error, :project_scheduled_for_deletion}
      {:error, :connection_not_for_this_project}    repo-connection actor only

  So `{:ok, _}` is not itself an authorisation result — a non-member of a live
  project gets `role: nil`, which support access can still make meaningful.

  Two support fields, deliberately. `support_user?` is the raw account flag.
  `support?` additionally requires the project's `allow_support_access`.
  Anything granting access to a customer's project wants `support?`.

  A `%ProjectRepoConnection{}` has no membership row, so its standing *is*
  which project it belongs to; `fetch/2` checks that, and its `role` is always
  `nil`. Ownership is checked before liveness, so a connection learns nothing
  about a project that is not its own.

  Scheduling deletion removes no membership rows and revokes no token, so this
  refusal is the whole of the offboarding gate during the purge window.

  ## When not to reach for it

    * `ProjectUsers` self-actions — they act on a *specific* membership row and
      ask whether it is the caller's own, which a scope cannot answer.
    * `Sandboxes` `:cancel_scheduled_deletion` — its subject is scheduled by
      definition, so the liveness gate would make restore impossible.
    * `Provisioning`'s `%Project{id: nil}` clause — no row to read, no members
      to consult.

  Every other project-scoped decision resolves here; no policy module reads
  `Project.scheduled_deletion` directly.

  Likewise, no policy module reads `requires_mfa`/`mfa_enabled` directly. That
  rule is written once, privately, below; `mfa_satisfied?` is the only way to
  reach it.
  """
  import Ecto.Query

  alias Lightning.Accounts.User
  alias Lightning.Projects.Project
  alias Lightning.Projects.ProjectUser
  alias Lightning.Repo
  alias Lightning.VersionControl.ProjectRepoConnection

  # `mfa_satisfied?` defaults to false so a `%Scope{}` that never went through
  # `build/2` — a fixture, or a clause for a future actor type that forgets to
  # set it — fails closed rather than silently bypassing the requirement.
  defstruct [
    :project,
    :actor,
    :project_user,
    :role,
    support_user?: false,
    support?: false,
    mfa_satisfied?: false
  ]

  @type t :: %__MODULE__{
          project: Project.t(),
          actor: actor(),
          project_user: ProjectUser.t() | nil,
          role: :owner | :admin | :editor | :viewer | nil,
          support_user?: boolean(),
          support?: boolean(),
          mfa_satisfied?: boolean()
        }

  @typedoc """
  Whoever is asking. A `%User{}` may hold a role; a `%ProjectRepoConnection{}`
  never does.
  """
  @type actor :: User.t() | ProjectRepoConnection.t()

  @typedoc """
  Anything that identifies a project: a loaded `%Project{}`, a project id, or
  any struct or map carrying a `:project_id` — a `%Dataclip{}`, a
  `%Collection{}`, a `%Projects.File{}`, a `%ProjectUser{}`.
  """
  # The map member is deliberately open — a closed `%{project_id: Ecto.UUID.t()}`
  # would put every real caller's struct out of contract.
  @type subject ::
          Project.t()
          | Ecto.UUID.t()
          | %{:project_id => Ecto.UUID.t(), optional(any()) => any()}
          | nil

  @type error ::
          :no_such_project
          | :project_scheduled_for_deletion
          | :connection_not_for_this_project

  @doc """
  The actor's standing in the project.

  Returns `{:error, :project_scheduled_for_deletion}` for a project that is
  winding down, `{:error, :no_such_project}` when the subject does not identify
  a project that exists, and — for a `%ProjectRepoConnection{}` actor —
  `{:error, :connection_not_for_this_project}` when the resolved project is not
  the one the connection belongs to.
  """
  @spec fetch(actor(), subject()) :: {:ok, t()} | {:error, error()}
  def fetch(%User{} = user, subject) do
    with {:ok, project} <- resolve_project(subject),
         :ok <- still_operable(project) do
      {:ok, build(user, project)}
    end
  end

  # Ownership before liveness, deliberately, and pinned by a test. Reversed, a
  # connection asking about someone else's project would be told whether that
  # project is being wound down.
  def fetch(%ProjectRepoConnection{} = repo_connection, subject) do
    with {:ok, project} <- resolve_project(subject),
         :ok <- connection_owns?(repo_connection, project),
         :ok <- still_operable(project) do
      {:ok, build(repo_connection, project)}
    end
  end

  @doc """
  Whether the user holds one of `roles` in the project.

  `false` for a project that does not exist or is scheduled for deletion,
  `false` for a user with no membership row, and `false` for a user who has
  not met the project's MFA requirement. It never consults `support?`, so a
  rule that admits a support user has to decide on the `%Scope{}` itself.
  """
  @spec role_in?(User.t(), subject(), [atom()]) :: boolean()
  def role_in?(%User{} = user, subject, roles) do
    case fetch(user, subject) do
      {:ok, %__MODULE__{role: role, mfa_satisfied?: mfa_satisfied?}} ->
        role in roles and mfa_satisfied?

      {:error, _reason} ->
        false
    end
  end

  defp still_operable(%Project{scheduled_deletion: nil}), do: :ok

  defp still_operable(%Project{}),
    do: {:error, :project_scheduled_for_deletion}

  # Answered here rather than at the call site so no policy can forget the
  # comparison. The repeated `id` binds both patterns to the same value.
  defp connection_owns?(%ProjectRepoConnection{project_id: id}, %Project{id: id}),
    do: :ok

  defp connection_owns?(%ProjectRepoConnection{}, %Project{}),
    do: {:error, :connection_not_for_this_project}

  # A subject names a project; it does not describe one. Even a `%Project{}` is
  # read for its id and reloaded, so no caller can assert its own standing from
  # a struct it happens to hold — whether assembled in code or loaded before the
  # facts changed.
  defp resolve_project(%Project{id: id}), do: load(id)
  defp resolve_project(%{project_id: id}), do: load(id)
  defp resolve_project(id) when is_binary(id), do: load(id)
  defp resolve_project(_), do: {:error, :no_such_project}

  # Repo.get raises Ecto.Query.CastError on a malformed binary_id, which would
  # turn a denial into a 500. Cast first.
  defp load(id) when is_binary(id) do
    with {:ok, uuid} <- Ecto.UUID.cast(id),
         %Project{} = project <- Repo.get(Project, uuid) do
      {:ok, project}
    else
      _ -> {:error, :no_such_project}
    end
  end

  defp load(_), do: {:error, :no_such_project}

  defp build(%User{} = user, %Project{} = project) do
    project_user =
      Repo.one(
        from pu in ProjectUser,
          where: pu.project_id == ^project.id and pu.user_id == ^user.id
      )

    %__MODULE__{
      project: project,
      actor: user,
      project_user: project_user,
      role: project_user && project_user.role,
      support_user?: user.support_user,
      support?: user.support_user and project.allow_support_access,
      mfa_satisfied?: mfa_satisfied?(project, user)
    }
  end

  # No membership row to look up, and no support-user concept. Its authority
  # comes from the token, which the caller has already verified.
  #
  # No MFA concept either — a machine credential cannot enrol — so the
  # exemption is set here rather than defaulted, to keep it a decision a
  # reviewer can see and a future actor type cannot inherit by accident.
  defp build(%ProjectRepoConnection{} = repo_connection, %Project{} = project) do
    %__MODULE__{
      project: project,
      actor: repo_connection,
      role: nil,
      mfa_satisfied?: true
    }
  end

  # Only an enrolled `true` counts; an unset flag is not enrolled.
  #
  # A support user is a human reading project data, so the rule binds them as
  # much as a member and nothing here consults `support_user`.
  defp mfa_satisfied?(%Project{requires_mfa: true}, %User{mfa_enabled: enrolled}),
    do: enrolled == true

  defp mfa_satisfied?(%Project{}, %User{}), do: true
end
