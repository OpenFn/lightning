defmodule Lightning.Scope do
  @moduledoc """
  The facts about whoever is calling, and their standing in a project right now.
  Policies decide from these facts. A Scope neither authenticates the caller nor
  decides what it may do.

  `new/1` gives the facts about the caller alone: the `grants` its token
  carries (`:all` for a person), its `instance_role`, MFA status, and whether it
  can own a credential (only a person can). `fetch/2` adds one project's facts,
  including whether it is scheduled for deletion, and `fetch_all/2` does the
  same for several projects in one query. On the API,
  `LightningWeb.Plugs.AuthorizeAction` builds the first and
  `LightningWeb.API.Target` the second.

      {:ok, %Scope{role: :editor}}
      {:ok, %Scope{role: nil}}                      no membership row
      {:ok, %Scope{scheduled_for_deletion?: true}}  scheduled for deletion
      {:error, :no_such_project}                    no such project, to an
                                                    operator or a superuser
      {:error, :invalid_id}                         an id that isn't a UUID, to
                                                    an operator or a superuser
      {:error, :no_standing}                        no such project or an id
                                                    that isn't a UUID, to anyone
                                                    else, or a repo connection
                                                    naming another project

  So `{:ok, _}` is not permission. A non-member of a live project gets
  `role: nil`, which support access can still make meaningful. Whether the
  facts are enough for an action is the policy's judgement, through
  `Lightning.Policies.Decision`.

  The one refusal `fetch/2` makes itself is for a `%ProjectRepoConnection{}`.
  It has no membership row, so its standing is which project it belongs to, and
  its `role` is always `nil`. Ownership is checked before anything else is read,
  so a connection learns nothing about a project that is not its own, and hears
  the same `:no_standing` a policy gives a user with no membership row.

  A `%ServiceAccount{}` has no membership row either and is not tied to one
  project, so its `role` is always `nil`. Its `instance_role` is `:operator`,
  which `holds_role?/2` treats as holding every project role.

  Two support fields, deliberately. `support_user?` is the account flag.
  `support?` also requires the project's `allow_support_access`. Anything
  granting access to a customer's project wants `support?`.

  Scheduling deletion removes no membership rows and revokes no token, so
  during the purge window only the policies' check of `scheduled_for_deletion?`
  keeps members out. Policies read `scheduled_for_deletion?` and
  `mfa_satisfied?` here, never `Project.scheduled_deletion`, `requires_mfa` or
  `mfa_enabled`. The MFA rule is written once, privately, in this module. The
  exception is `Lightning.Policies.Sandboxes` `:cancel_scheduled_deletion`,
  which reads its subject's role directly, since its subject is scheduled by
  definition.
  """
  import Ecto.Query

  alias Lightning.Accounts.User
  alias Lightning.Projects.Project
  alias Lightning.Projects.ProjectUser
  alias Lightning.Repo
  alias Lightning.ServiceAccount
  alias Lightning.Validators
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

  @type error :: :no_such_project | :invalid_id | :no_standing

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

  # A repo connection holds only `projects:provision`, so every other
  # grant-checked action refuses it.
  def new(%ProjectRepoConnection{} = repo_connection) do
    %__MODULE__{
      actor: repo_connection,
      grants: MapSet.new(["projects:provision"]),
      mfa_satisfied?: true
    }
  end

  @doc """
  The actor's standing in the project. Given a `%Scope{}` from `new/1`, adds
  the project's facts to it rather than building it again.

  When the subject does not identify a project that exists, a caller with
  `instance_wide?/1` access gets `{:error, :invalid_id}` for an id that isn't a
  UUID, or a value that isn't an id at all, and `{:error, :no_such_project}`
  for any other. Anyone else gets `{:error, :no_standing}`, the same answer as
  for a project they can't see.

  Returns `{:error, :no_standing}` when a `%ProjectRepoConnection{}` actor names
  a project other than the connection's own. A project scheduled for deletion
  resolves, with `scheduled_for_deletion?` set; refusing it is the policy's
  call.

  A `%ServiceAccount{}` resolves any project, with no role.
  """
  @spec fetch(t() | actor(), subject()) :: {:ok, t()} | {:error, error()}
  def fetch(%__MODULE__{} = scope, subject) do
    with {:ok, id} <- subject_id(subject),
         [result] <- resolve(scope, [id]) do
      result
    else
      [] -> refuse_unknown(scope, :no_such_project)
      {:error, reason} -> refuse_unknown(scope, reason)
    end
  end

  def fetch(actor, subject), do: fetch(new(actor), subject)

  @doc """
  The actor's standing in each of several projects, read in one query, as a
  map from project id to the scope `fetch/2` would give.

  An id that is malformed, names no project, or names a project a
  `%ProjectRepoConnection{}` actor does not belong to is absent from the map.
  """
  @spec fetch_all(t() | actor(), [Ecto.UUID.t()]) :: %{Ecto.UUID.t() => t()}
  def fetch_all(%__MODULE__{} = scope, project_ids) do
    for {:ok, %__MODULE__{project: project} = project_scope} <-
          resolve(scope, project_ids),
        into: %{},
        do: {project.id, project_scope}
  end

  def fetch_all(actor, project_ids), do: fetch_all(new(actor), project_ids)

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
  or support access. This is the one definition of standing, so reading a
  project and being blocked by MFA can't disagree about it.
  """
  @spec has_standing?(t()) :: boolean()
  def has_standing?(%__MODULE__{} = scope),
    do: holds_role?(scope, [:owner, :admin, :editor, :viewer]) or scope.support?

  @doc "Whether the caller acts for the instance on every project."
  @spec operator?(t()) :: boolean()
  def operator?(%__MODULE__{instance_role: instance_role}),
    do: instance_role == :operator

  @doc """
  Whether the caller may learn which projects exist: an operator or a
  superuser. Anyone else is told nothing about a project they have no standing
  on, including that it doesn't exist.
  """
  @spec instance_wide?(t()) :: boolean()
  def instance_wide?(%__MODULE__{instance_role: instance_role}),
    do: instance_role in [:operator, :superuser]

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

  defp refuse_unknown(scope, reason) do
    if instance_wide?(scope), do: {:error, reason}, else: {:error, :no_standing}
  end

  # Answered here rather than at the call site so no policy can forget the
  # comparison. The repeated `id` binds both patterns to the same value. Another
  # project is refused like a missing one: the connection has no standing on
  # it, and a distinct refusal would confirm it exists.
  defp connection_owns?(%ProjectRepoConnection{project_id: id}, %Project{id: id}),
    do: :ok

  defp connection_owns?(%ProjectRepoConnection{}, %Project{}),
    do: {:error, :no_standing}

  defp connection_owns?(_actor, %Project{}), do: :ok

  # Ownership before any other fact, deliberately, and pinned by a test.
  # Reversed, a connection asking about someone else's project would be told
  # whether that project is being wound down.
  defp resolve(%__MODULE__{actor: actor} = scope, project_ids) do
    for {project, project_user} <- load(actor, project_ids) do
      with :ok <- connection_owns?(actor, project),
           do: {:ok, put_project(scope, project, project_user)}
    end
  end

  # A subject names a project; it does not describe one. Even a `%Project{}` is
  # read for its id and reloaded, so no caller can assert its own standing from
  # a struct it happens to hold — whether assembled in code or loaded before the
  # facts changed.
  defp subject_id(%Project{id: id}), do: project_id(id)
  defp subject_id(%{project_id: id}), do: project_id(id)
  defp subject_id(id), do: project_id(id)

  defp project_id(nil), do: {:error, :no_such_project}

  defp project_id(id) when is_binary(id) do
    if Validators.valid_uuid?(id), do: {:ok, id}, else: {:error, :invalid_id}
  end

  defp project_id(_id), do: {:error, :invalid_id}

  # Each project comes with the user's own membership row, or nil. Querying a
  # malformed binary_id raises Ecto.Query.CastError, which would turn a denial
  # into a 500, so ids are checked first.
  defp load(actor, project_ids) do
    case Enum.filter(project_ids, &Validators.valid_uuid?/1) do
      [] -> []
      uuids -> Repo.all(load_query(actor, uuids))
    end
  end

  defp load_query(%User{id: user_id}, uuids) do
    from p in Project,
      where: p.id in ^uuids,
      left_join: pu in ProjectUser,
      on: pu.project_id == p.id and pu.user_id == ^user_id,
      select: {p, pu}
  end

  defp load_query(_actor, uuids),
    do: from(p in Project, where: p.id in ^uuids, select: {p, nil})

  defp put_project(
         %__MODULE__{actor: %User{} = user} = scope,
         project,
         project_user
       ) do
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

  # Any other actor has no membership row, and no support-user or MFA concept.
  # A machine credential cannot enrol, so `new/1` sets the exemption where a
  # reviewer can see it.
  defp put_project(%__MODULE__{} = scope, project, _project_user),
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
