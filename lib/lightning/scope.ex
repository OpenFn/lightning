defmodule Lightning.Scope do
  @moduledoc """
  The facts about whoever is calling, and their standing in a project right now.

  `new/1` gives the facts about the caller alone: the `grants` its token
  carries (`:all` for a person), its `instance_role`, MFA status, and whether
  it can own a credential (only a person can). `fetch/2`
  adds the facts about one project, including whether it is scheduled for
  deletion, and refuses only a project that does not exist. Whether that
  standing is enough for an action is the policy's judgement — see
  `Lightning.Policies.ProjectUsers.permitted?/2`.

      {:ok, %Scope{role: :editor}}
      {:ok, %Scope{role: nil}}                      no membership row
      {:ok, %Scope{scheduled_for_deletion?: true}}  winding down
      {:error, :no_such_project}
      {:error, :connection_not_for_this_project}    repo-connection actor only

  So `{:ok, _}` is not itself an authorisation result — a non-member of a live
  project gets `role: nil`, which support access can still make meaningful.

  Two support fields, deliberately. `support_user?` is the raw account flag.
  `support?` additionally requires the project's `allow_support_access`.
  Anything granting access to a customer's project wants `support?`.

  A `%ProjectRepoConnection{}` has no membership row, so its standing *is*
  which project it belongs to; `fetch/2` checks that, and its `role` is always
  `nil`. Ownership is checked before anything else is read, so a connection
  learns nothing about a project that is not its own.

  A `%ServiceAccount{}` has no membership row either and is not tied to one
  project; its `role` is always `nil`. Its `instance_role` is `:operator`, which
  `holds_role?/2` treats as holding every project role.

  Scheduling deletion removes no membership rows and revokes no token, so the
  policies refusing a scope with `scheduled_for_deletion?` set is the whole of
  what keeps its members out during the purge window.

  ## When not to reach for it

    * `Sandboxes` `:cancel_scheduled_deletion` — it reads its subject's role
      directly, since its subject is scheduled by definition.
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
  alias Lightning.ServiceAccount
  alias Lightning.VersionControl.ProjectRepoConnection

  # `grants`, `mfa_satisfied?` and `can_own_credentials?` default to refusing,
  # so a `%Scope{}` that never went through `new/1` — a fixture, or a clause for
  # a future actor type that forgets to set them — fails closed rather than
  # silently passing.
  @enforce_keys [:actor]
  defstruct [
    :actor,
    grants: MapSet.new(),
    instance_role: nil,
    support_user?: false,
    mfa_satisfied?: false,
    can_own_credentials?: false,
    project: nil,
    project_user: nil,
    role: nil,
    support?: false,
    scheduled_for_deletion?: false
  ]

  @type t :: %__MODULE__{
          actor: actor(),
          grants: :all | MapSet.t(String.t()),
          instance_role: :superuser | :operator | nil,
          support_user?: boolean(),
          mfa_satisfied?: boolean(),
          can_own_credentials?: boolean(),
          project: Project.t() | nil,
          project_user: ProjectUser.t() | nil,
          role: :owner | :admin | :editor | :viewer | nil,
          support?: boolean(),
          scheduled_for_deletion?: boolean()
        }

  @typedoc """
  Whoever is asking. A `%User{}` may hold a role; a `%ProjectRepoConnection{}`
  and a `%ServiceAccount{}` never do.
  """
  @type actor :: Lightning.Actor.t() | ProjectRepoConnection.t()

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
          | :connection_not_for_this_project

  @doc """
  The facts about the caller alone, with no project.

  No project means no MFA requirement to meet, so `mfa_satisfied?` is `true`.
  """
  @spec new(actor()) :: t()
  def new(%User{} = user) do
    %__MODULE__{
      actor: user,
      grants: :all,
      instance_role: if(user.role == :superuser, do: :superuser),
      support_user?: user.support_user,
      mfa_satisfied?: true,
      can_own_credentials?: true
    }
  end

  def new(%ServiceAccount{} = account) do
    %__MODULE__{
      actor: account,
      grants: account.grants,
      instance_role: :operator,
      mfa_satisfied?: true
    }
  end

  # A repo connection holds no grant, so every grant-checked action refuses it.
  def new(%ProjectRepoConnection{} = repo_connection) do
    %__MODULE__{actor: repo_connection, mfa_satisfied?: true}
  end

  @doc """
  The actor's standing in the project. Given a `%Scope{}` from `new/1`, adds
  the project's facts to it rather than building it again.

  Returns `{:error, :no_such_project}` when the subject does not identify a
  project that exists, and — for a `%ProjectRepoConnection{}` actor —
  `{:error, :connection_not_for_this_project}` when the resolved project is not
  the one the connection belongs to. A project scheduled for deletion resolves,
  with `scheduled_for_deletion?` set; refusing it is the policy's call.

  A `%ServiceAccount{}` resolves any project, with no role.
  """
  @spec fetch(t() | actor(), subject()) :: {:ok, t()} | {:error, error()}
  # Ownership before any other fact, deliberately, and pinned by a test.
  # Reversed, a connection asking about someone else's project would be told
  # whether that project is being wound down.
  def fetch(%__MODULE__{actor: actor} = scope, subject) do
    with {:ok, project} <- resolve_project(subject),
         :ok <- connection_owns?(actor, project) do
      {:ok, put_project(scope, project)}
    end
  end

  def fetch(actor, subject), do: fetch(new(actor), subject)

  @doc "Whether the caller's token carries `grant`. A person holds every grant."
  @spec allows?(t(), String.t()) :: boolean()
  def allows?(%__MODULE__{grants: :all}, _grant), do: true

  def allows?(%__MODULE__{grants: grants}, grant),
    do: MapSet.member?(grants, grant)

  @doc """
  Whether the caller stands in one of `roles` in the scope's project. An
  operator stands in every role. Standing only: it does not consult MFA or
  whether the project is being deleted.
  """
  @spec holds_role?(t(), [atom()]) :: boolean()
  def holds_role?(%__MODULE__{} = scope, roles),
    do: operator?(scope) or scope.role in roles

  @doc """
  Whether the caller has any standing in the scope's project at all: a role,
  or support access. The one definition; reading a project and being blocked
  only by MFA are both this plus or minus the MFA fact.
  """
  @spec has_standing?(t()) :: boolean()
  def has_standing?(%__MODULE__{} = scope),
    do: holds_role?(scope, [:owner, :admin, :editor, :viewer]) or scope.support?

  @doc "Whether the caller acts for the instance on every project."
  @spec operator?(t()) :: boolean()
  def operator?(%__MODULE__{instance_role: instance_role}),
    do: instance_role == :operator

  @doc """
  Whether `subject` names this scope's project: the project itself, its id, or
  anything carrying its `project_id`.
  """
  @spec describes?(t(), term()) :: boolean()
  def describes?(%__MODULE__{project: %Project{id: id}}, %Project{id: id}),
    do: true

  def describes?(%__MODULE__{project: %Project{id: id}}, %{project_id: id}),
    do: true

  def describes?(%__MODULE__{project: %Project{id: id}}, subject)
      when is_binary(subject),
      do: Ecto.UUID.cast(subject) == {:ok, id}

  def describes?(%__MODULE__{}, _subject), do: false

  @doc """
  Whether the actor holds one of `roles` in the project.

  `false` for a project that does not exist or is scheduled for deletion,
  `false` for a user with no membership row, and `false` for a user who has
  not met the project's MFA requirement. It never consults `support?`, so a
  rule that admits a support user has to decide on the `%Scope{}` itself.
  """
  @spec role_in?(actor(), subject(), [atom()]) :: boolean()
  def role_in?(actor, subject, roles) do
    case fetch(actor, subject) do
      {:ok, %__MODULE__{} = scope} ->
        scope.mfa_satisfied? and not scope.scheduled_for_deletion? and
          holds_role?(scope, roles)

      {:error, _reason} ->
        false
    end
  end

  # Answered here rather than at the call site so no policy can forget the
  # comparison. The repeated `id` binds both patterns to the same value.
  defp connection_owns?(%ProjectRepoConnection{project_id: id}, %Project{id: id}),
    do: :ok

  defp connection_owns?(%ProjectRepoConnection{}, %Project{}),
    do: {:error, :connection_not_for_this_project}

  defp connection_owns?(_actor, %Project{}), do: :ok

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

  defp put_project(%__MODULE__{actor: %User{} = user} = scope, project) do
    project_user =
      Repo.one(
        from pu in ProjectUser,
          where: pu.project_id == ^project.id and pu.user_id == ^user.id
      )

    %{
      scope
      | project: project,
        project_user: project_user,
        role: project_user && project_user.role,
        support?: scope.support_user? and project.allow_support_access,
        mfa_satisfied?: mfa_satisfied?(project, user),
        scheduled_for_deletion?: scheduled?(project)
    }
  end

  # No membership row to look up, and no support-user or MFA concept: a machine
  # credential cannot enrol, so `new/1` sets the exemption where a reviewer can
  # see it.
  defp put_project(%__MODULE__{} = scope, project),
    do: %{scope | project: project, scheduled_for_deletion?: scheduled?(project)}

  defp scheduled?(%Project{scheduled_deletion: scheduled_deletion}),
    do: not is_nil(scheduled_deletion)

  # Only an enrolled `true` counts; an unset flag is not enrolled.
  #
  # A support user is a human reading project data, so the rule binds them as
  # much as a member and nothing here consults `support_user`.
  defp mfa_satisfied?(%Project{requires_mfa: true}, %User{mfa_enabled: enrolled}),
    do: enrolled == true

  defp mfa_satisfied?(%Project{}, %User{}), do: true
end
