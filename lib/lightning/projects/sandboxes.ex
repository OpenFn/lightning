defmodule Lightning.Projects.Sandboxes do
  @moduledoc """
  Manage **sandbox projects** - isolated copies of existing projects for safe experimentation.

  Sandboxes allow developers to test changes, experiment with workflows, and collaborate
  without affecting production projects. They share credentials with their parent but
  maintain separate workflow execution environments.

  ## What gets copied to a sandbox

  * **Project settings**: retention policies, concurrency limits, MFA requirements
  * **Workflow structure**: jobs, triggers (disabled), edges, and node positions
  * **Credentials**: references to parent credentials (no secrets duplicated)
  * **Keychain metadata**: cloned for jobs that use them
  * **Version history**: latest workflow version per workflow
  * **Optional dataclips**: named clips of specific types can be selectively copied

  ## Operations

  * `provision/3` - Create a new sandbox from a parent project
  * `merge/4` - Merge a sandbox into its target (workflows + collections)
  * `update_sandbox/3` - Update sandbox name, color, or environment
  * `schedule_sandbox_deletion/2` - Soft-delete a sandbox and its descendants;
    they remain in the database for a grace period before being purged
  * `cancel_scheduled_sandbox_deletion/2` - Restore a scheduled sandbox subtree
    while it is still within its grace period (admin recovery path)
  * `delete_sandbox/2` - Hard-delete a sandbox and all its descendants
    immediately (used by the Oban purge worker after the grace period elapses)

  ## Authorization

  * **Provisioning**: Requires `:editor`, `:admin`, or `:owner` role on the parent project
  * **Merge**: Requires `:editor`, `:admin`, or `:owner` role on the target project
  * **Updates/Deletion**: Requires `:owner` or `:admin` role on the sandbox itself,
                          or `:owner` or `:admin` on the root project

  ## Transaction safety

  All operations are performed within database transactions to ensure consistency.
  Failed operations leave no partial state behind.
  """
  import Ecto.Query

  alias Lightning.Accounts.User
  alias Lightning.Collections
  alias Lightning.Collections.Collection
  alias Lightning.Credentials.KeychainCredential
  alias Lightning.Credentials.Scoping
  alias Lightning.Policies.Permissions
  alias Lightning.Projects.MergeProjects
  alias Lightning.Projects.Project
  alias Lightning.Projects.ProjectCredential
  alias Lightning.Projects.ProjectLimiter
  alias Lightning.Projects.Provisioner
  alias Lightning.Projects.SandboxPromExPlugin
  alias Lightning.Repo
  alias Lightning.Services.CollectionHook
  alias Lightning.Workflows
  alias Lightning.Workflows.Edge
  alias Lightning.Workflows.Job
  alias Lightning.Workflows.Trigger
  alias Lightning.Workflows.Workflow
  alias Lightning.Workflows.WorkflowVersion
  alias Lightning.WorkflowVersions

  require Logger

  @typedoc """
  Attributes for creating a new sandbox via `provision/3`.

  ## Required
  * `:name` - Sandbox name (must be unique within the parent project)

  ## Optional
  * `:color` - UI color hex string (e.g. `"#336699"`)
  * `:env` - Environment identifier (e.g. `"staging"`, `"dev"`)
  * `:dataclip_ids` - UUIDs of dataclips to copy (only copies named dataclips
    of types `:global`, `:saved_input`, or `:http_request`)

  The sandbox's `project_users` are derived from the parent project: every
  parent user is copied across with their role preserved, except the parent
  owner who is demoted to `:admin`. The `actor` is then set as the sandbox
  owner (replacing any other role they may have had on the parent). To add
  a user to the sandbox who is not on the parent, call
  `Lightning.Projects.add_project_users/3` after provision returns — that
  path goes through the seat-limit check.
  """
  @type provision_attrs :: %{
          required(:name) => String.t(),
          optional(:color) => String.t() | nil,
          optional(:env) => String.t() | nil,
          optional(:dataclip_ids) => [Ecto.UUID.t()]
        }

  @cloned_project_fields ~w(
    allow_support_access concurrency description requires_mfa
    retention_policy history_retention_period dataclip_retention_period
  )a

  @allowed_dataclip_types [:global, :saved_input, :http_request]

  @doc """
  Creates a new sandbox project by cloning from a parent project.

  The creator becomes the sandbox owner, and all workflow triggers are disabled.
  Credentials are shared (not duplicated) between parent and sandbox.

  ## Parameters
  * `parent` - Project to clone from
  * `actor` - User creating the sandbox (needs `:editor`, `:admin`, or `:owner` role on parent)
  * `attrs` - Creation attributes (see `t:provision_attrs/0`)

  ## Returns
  * `{:ok, sandbox_project}` - Successfully created sandbox
  * `{:error, :unauthorized}` - Actor lacks permission on parent
  * `{:error, :nesting_too_deep}` - Parent is already at `Lightning.Config.max_sandbox_nesting_depth/0`
  * `{:error, changeset}` - Validation or database error

  ## Example
      {:ok, sandbox} = Sandboxes.provision(parent_project, user, %{
        name: "test-environment",
        color: "#336699"
      })

  ## Concurrency note

  The nesting-depth check runs inside the same `Repo.transaction` as the
  sandbox insert, but PostgreSQL's default READ COMMITTED isolation does
  not lock the parent's ancestry. A concurrent committed reparent of
  `parent` or any of its ancestors between the depth read and the insert
  could place the new sandbox one level above the cap. Lightning has no
  reparenting code path today, so this is theoretical; if a re-homing
  feature ships, this check should be tightened with `SELECT FOR UPDATE`
  on the ancestor chain.
  """
  @spec provision(Project.t(), User.t(), provision_attrs) ::
          {:ok, Project.t()}
          | {:error,
             :unauthorized
             | :nesting_too_deep
             | Ecto.Changeset.t()
             | term()}
  def provision(%Project{} = parent, %User{} = actor, attrs) do
    if Permissions.can?(:sandboxes, :provision_sandbox, actor, parent) do
      create_sandbox_from_parent(parent, actor, attrs)
    else
      {:error, :unauthorized}
    end
  end

  defp nesting_depth_exceeded?(%Project{id: parent_id}) do
    Lightning.Projects.depth_of(parent_id) >=
      Lightning.Config.max_sandbox_nesting_depth()
  end

  @doc """
  Merges a sandbox into its target project.

  Imports the sandbox's workflow configuration into the target via the
  provisioner and synchronises collection names. Runs inside a single
  transaction. Collection data is never copied.

  Callers must authorise the merge before calling (e.g. `:merge_sandbox`).

  ## Parameters
  * `source` - The sandbox project being merged
  * `target` - The project receiving the merge
  * `actor` - The user performing the merge
  * `opts` - Merge options (`:selected_workflow_ids`,
    `:deleted_target_workflow_ids`, `:selected_credential_ids`)

  ## Credential attachment

  A credential that lives only in the sandbox (the target has no
  `project_credential` for its underlying `credential_id`) would otherwise be
  dropped on merge, since the remap only matches on shared credentials. Pass
  `:selected_credential_ids` (a list of the sandbox `project_credential` ids the
  caller chose to carry over) and each one is attached to the target before the
  document is imported, so the remap finds a match instead of dropping it.
  Sandbox `project_credentials` left out of the list stay dropped.

  Keychain credentials are handled analogously: a keychain that lives only in the
  sandbox and is used by a to-be-merged workflow is attached to the target (along
  with its default credential) before the document is imported, so the keychain
  remap name-matches it instead of dropping it. Attachment follows the same scope
  as the merge, so a partial merge (via `:selected_workflow_ids`) only carries
  over keychains used by the selected workflows. A keychain whose name already
  exists in the target is left as the target's own.

  ## Returns
  * `{:ok, updated_target}` - Merge succeeded
  * `{:error, merge_error}` - Merge failed, classified into a domain reason

  Failures are returned as typed reasons (see `t:merge_error/0`) so callers can
  render user-facing copy without inspecting changeset internals. The full
  validation detail is logged for diagnosis.
  """
  @type merge_error ::
          :merge_failed | Lightning.Extensions.UsageLimiting.message()

  @spec merge(Project.t(), Project.t(), User.t(), map()) ::
          {:ok, Project.t()} | {:error, merge_error()}
  def merge(
        %Project{} = source,
        %Project{} = target,
        %User{} = actor,
        opts \\ %{}
      ) do
    selected_credential_ids = Map.get(opts, :selected_credential_ids, [])

    # `:merge_sandbox` allows editors, but deleting collections needs owner/admin.
    # Gate only the destructive half so an editor can merge without pruning data.
    allow_collection_deletions? =
      Permissions.can?(:collections, :manage_collection, actor, target)

    Repo.transact(fn ->
      # Preload once so both attach_sandbox_keychains and merge_project derive
      # the carried-workflow set from the same in-memory assoc (their
      # carried_source_workflows/2 calls use a non-forced preload and skip the query).
      source = Repo.preload(source, workflows: [:jobs, :triggers, :edges])

      with :ok <-
             attach_selected_credentials(source, target, selected_credential_ids),
           :ok <- attach_sandbox_keychains(source, target, opts),
           # Re-preload so the credential and keychain remaps see the
           # just-attached associations; merge_project skips the preload if
           # they're already loaded.
           target =
             Repo.preload(
               target,
               [project_credentials: [], keychain_credentials: []],
               force: true
             ),
           merge_doc = MergeProjects.merge_project(source, target, opts),
           {:ok, updated_target} <-
             Provisioner.import_document(target, actor, merge_doc,
               allow_stale: true
             ),
           :ok <- reject_out_of_project_credentials(target),
           {:ok, _} <-
             sync_collections(source, target,
               allow_deletions: allow_collection_deletions?
             ) do
        {:ok, updated_target}
      end
    end)
    |> case do
      {:ok, _} = ok -> ok
      {:error, reason} -> {:error, classify_merge_error(reason)}
    end
  end

  # Defence-in-depth backstop: after the document lands, re-read the target's
  # persisted jobs and roll the whole merge back if any references a credential
  # or keychain owned by a different project. On the live path
  # Provisioner.import_document runs its own project-wide scoping guard (a strict
  # superset of this scan, covering jobs and channels) and rolls back first, so
  # this firing at all means an upstream guard regressed — most concretely the
  # fail-open Map.get identity fallthrough in MergeProjects.merge_project/3's
  # keychain remap, or a future change that stops the merge routing through the
  # provisioner chokepoint. Scanning every target job is a safe superset:
  # untouched, already-valid jobs scope clean.
  defp reject_out_of_project_credentials(%Project{id: target_id}) do
    case Scoping.out_of_project_references(
           target_id,
           Scoping.job_refs_for_project(target_id)
         ) do
      [] -> :ok
      violations -> {:error, {:out_of_project_credentials, violations}}
    end
  end

  # Attaches the chosen sandbox-only credentials to the target so the merge
  # remap can match them. The credential diff is recomputed from the database
  # rather than trusting the caller's list verbatim: only sandbox
  # project_credentials whose underlying credential the target still lacks are
  # attached, and ON CONFLICT DO NOTHING guards against a concurrent attach.
  defp attach_selected_credentials(_source, _target, []), do: :ok

  defp attach_selected_credentials(source, target, selected_credential_ids) do
    selected_set = MapSet.new(selected_credential_ids)

    target_credential_ids =
      from(pc in ProjectCredential,
        where: pc.project_id == ^target.id,
        select: pc.credential_id
      )
      |> Repo.all()
      |> MapSet.new()

    rows =
      from(pc in ProjectCredential,
        where: pc.project_id == ^source.id,
        select: %{id: pc.id, credential_id: pc.credential_id}
      )
      |> Repo.all()
      |> Enum.filter(fn pc ->
        MapSet.member?(selected_set, pc.id) and
          not MapSet.member?(target_credential_ids, pc.credential_id)
      end)
      |> build_target_credential_rows(target.id)

    Repo.insert_all(ProjectCredential, rows,
      on_conflict: :nothing,
      conflict_target: [:project_id, :credential_id]
    )

    :ok
  end

  defp build_target_credential_rows(source_credentials, target_id) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    Enum.map(source_credentials, fn pc ->
      %{
        id: Ecto.UUID.generate(),
        project_id: target_id,
        credential_id: pc.credential_id,
        inserted_at: now,
        updated_at: now
      }
    end)
  end

  # Attaches any sandbox-only keychain used by a to-be-merged source job to the
  # target so the keychain remap in merge_project/3 can name-match it. Derives
  # the keychains from the same carried-workflow set the merge document is built
  # from (MergeProjects.carried_source_workflows/2), so it shares the merge's
  # live-only and `:selected_workflow_ids` scope: soft-deleted or unselected
  # source workflows' keychains are never attached, matching what the document
  # actually carries. A keychain whose name already exists in the target is left
  # alone (the remap resolves it to the target's own keychain). For a genuinely
  # sandbox-only keychain we also attach its default credential first, so the
  # KeychainCredential changeset's validate_default_credential_belongs_to_project
  # passes against the target. Returns `{:error, changeset}` on the first genuine
  # insert failure so the merge transaction rolls back.
  defp attach_sandbox_keychains(source, target, opts) do
    target_keychain_names =
      from(k in KeychainCredential,
        where: k.project_id == ^target.id,
        select: k.name
      )
      |> Repo.all()
      |> MapSet.new()

    source
    |> MergeProjects.carried_source_workflows(opts)
    |> Enum.flat_map(& &1.jobs)
    |> Enum.map(& &1.keychain_credential_id)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
    |> load_source_keychains(source.id)
    |> Enum.reject(&MapSet.member?(target_keychain_names, &1.name))
    |> Enum.reduce_while(:ok, fn keychain, :ok ->
      case attach_keychain_to_target(keychain, target) do
        {:ok, _} -> {:cont, :ok}
        {:error, _} = error -> {:halt, error}
      end
    end)
  end

  # Only ever loads source-owned keychains: a job could, via changeset bypass,
  # point at a foreign keychain, but we attach only ones the sandbox owns. The
  # provisioner guard and backstop reject anything else.
  defp load_source_keychains([], _source_id), do: []

  defp load_source_keychains(ids, source_id) do
    from(k in KeychainCredential,
      where: k.id in ^ids and k.project_id == ^source_id
    )
    |> Repo.all()
  end

  defp attach_keychain_to_target(keychain, target) do
    attach_keychain_default_credential(keychain, target)

    # The project must be on the base struct so that
    # validate_default_credential_belongs_to_project can see it when
    # changeset/2 runs; put_assoc after the fact would skip the check.
    %KeychainCredential{
      project: target,
      project_id: target.id,
      created_by_id: keychain.created_by_id
    }
    |> KeychainCredential.changeset(%{
      name: keychain.name,
      path: keychain.path,
      default_credential_id: keychain.default_credential_id
    })
    |> Repo.insert(on_conflict: :nothing, conflict_target: [:name, :project_id])
  end

  defp attach_keychain_default_credential(
         %{default_credential_id: nil},
         _target
       ),
       do: :ok

  defp attach_keychain_default_credential(
         %{default_credential_id: credential_id},
         target
       ) do
    rows =
      build_target_credential_rows([%{credential_id: credential_id}], target.id)

    Repo.insert_all(ProjectCredential, rows,
      on_conflict: :nothing,
      conflict_target: [:project_id, :credential_id]
    )

    :ok
  end

  # A failed merge is sensitive (it can block or lose a user's work), so every
  # failure is logged at :error to surface in Sentry. A usage-limit message is
  # an expected, user-actionable block, so it passes through unlogged.
  defp classify_merge_error(%Ecto.Changeset{} = changeset) do
    Logger.error(
      "Sandbox merge failed. #{inspect(merge_error_details(changeset))}"
    )

    :merge_failed
  end

  defp classify_merge_error(%{text: _} = usage_limit_message),
    do: usage_limit_message

  defp classify_merge_error({:out_of_project_credentials, violations}) do
    details =
      Enum.map_join(violations, "; ", fn %{key: job_id, field: field} ->
        "job #{job_id} #{field}: #{Scoping.violation_message(field)}"
      end)

    Logger.error(
      "Sandbox merge failed. Out-of-project credential references " <>
        "survived the provisioner guard (backstop caught): #{details}"
    )

    :merge_failed
  end

  defp classify_merge_error(reason) do
    Logger.error("Sandbox merge failed. #{inspect(reason)}")
    :merge_failed
  end

  defp merge_error_details(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, _opts} -> message end)
  end

  @doc """
  Updates a sandbox project's basic attributes.

  ## Parameters
  * `sandbox` - Sandbox project to update (or sandbox ID as string)
  * `actor` - User performing the update (needs `:owner` or `:admin` role on sandbox)
  * `attrs` - Map with `:name`, `:color`, and/or `:env` keys

  ## Returns
  * `{:ok, updated_sandbox}` - Successfully updated sandbox
  * `{:error, :unauthorized}` - Actor lacks permission on sandbox
  * `{:error, :not_found}` - Sandbox ID not found (when using string ID)
  * `{:error, changeset}` - Validation error

  ## Example
    {:ok, updated} = Sandboxes.update_sandbox(sandbox, user, %{
      name: "new-name",
      color: "#ff6b35"
    })
  """
  @spec update_sandbox(Project.t() | Ecto.UUID.t(), User.t(), map()) ::
          {:ok, Project.t()}
          | {:error, :unauthorized | :not_found | Ecto.Changeset.t()}
  def update_sandbox(%Project{} = sandbox, %User{} = actor, attrs)
      when is_map(attrs) do
    Permissions.can?(
      :sandboxes,
      :update_sandbox,
      actor,
      sandbox
    )
    |> if do
      allowed_attrs = Map.take(attrs, [:name, :color, :env])
      Lightning.Projects.update_project(sandbox, allowed_attrs, actor)
    else
      {:error, :unauthorized}
    end
  end

  def update_sandbox(sandbox_id, %User{} = actor, attrs)
      when is_binary(sandbox_id) and is_map(attrs) do
    case Lightning.Projects.get_project(sandbox_id) do
      %Project{} = sandbox -> update_sandbox(sandbox, actor, attrs)
      nil -> {:error, :not_found}
    end
  end

  @doc """
  Returns `true` when `user` has an `:admin` or `:owner` role on any ancestor
  of `project`, walking the parent chain.

  Used to enforce the parent-admin floor rule: a user who is admin/owner on
  any ancestor project cannot be removed from, or downgraded within, a
  sandbox descended from that project.
  """
  @spec parent_admin?(Project.t(), User.t()) :: boolean()
  def parent_admin?(%Project{} = project, %User{} = user) do
    project
    |> ancestors()
    |> Enum.any?(fn ancestor ->
      Lightning.Projects.get_project_user_role(user, ancestor) in [
        :admin,
        :owner
      ]
    end)
  end

  defp ancestors(%Project{parent_id: nil}), do: []

  defp ancestors(%Project{parent_id: parent_id}) do
    case Lightning.Projects.get_project(parent_id) do
      nil -> []
      %Project{} = parent -> [parent | ancestors(parent)]
    end
  end

  @doc """
  Deletes a sandbox and all its descendant projects.

  ## Parameters
  * `sandbox` - Sandbox project to delete (or sandbox ID as string)
  * `actor` - User performing the deletion (needs `:owner` or `:admin` role on sandbox)

  ## Returns
  * `{:ok, deleted_sandbox}` - Successfully deleted sandbox and descendants
  * `{:error, :unauthorized}` - Actor lacks permission on sandbox
  * `{:error, :not_found}` - Sandbox ID not found (when using string ID)
  * `{:error, reason}` - Database or other deletion error

  ## Example
      {:ok, deleted} = Sandboxes.delete_sandbox(sandbox, user)
  """
  @spec delete_sandbox(Project.t() | Ecto.UUID.t(), User.t()) ::
          {:ok, Project.t()} | {:error, :unauthorized | :not_found | term()}
  def delete_sandbox(%Project{} = sandbox, %User{} = actor) do
    if Permissions.can?(:sandboxes, :delete_sandbox, actor, sandbox) do
      Lightning.Projects.delete_project(sandbox)
    else
      {:error, :unauthorized}
    end
  end

  def delete_sandbox(sandbox_id, %User{} = actor) when is_binary(sandbox_id) do
    case Lightning.Projects.get_project(sandbox_id) do
      %Project{} = sandbox -> delete_sandbox(sandbox, actor)
      nil -> {:error, :not_found}
    end
  end

  @doc """
  Schedules a sandbox and its entire descendant subtree for deletion.

  The sandbox stays in the database for a grace period (controlled by
  `PURGE_DELETED_AFTER_DAYS`) before the Oban purge worker permanently
  deletes it. During the grace period the sandbox is hidden from the
  parent's sandbox listing but remains recoverable via
  `cancel_scheduled_sandbox_deletion/2`.

  All triggers in the subtree are disabled so that scheduled work stops
  immediately. The scheduled timestamp is applied to the target and every
  descendant in a single transaction so the entire subtree shares a grace
  period and gets purged together.

  ## Cascade semantics

  Scheduling cascades through every descendant unconditionally. If a child
  sandbox was already scheduled separately (with an earlier timestamp), that
  earlier timestamp is overwritten with the new one. The intent is that
  scheduling a parent always synchronises the whole subtree's grace window;
  if you need a child to be purged on its original earlier timestamp, do not
  schedule the parent.

  ## Parameters
  * `sandbox` - Sandbox project to schedule (or sandbox ID as string)
  * `actor` - User performing the action (needs `:delete_sandbox` permission)

  ## Returns
  * `{:ok, scheduled_sandbox}` - Sandbox subtree scheduled for deletion
  * `{:error, :unauthorized}` - Actor lacks permission on the sandbox
  * `{:error, :not_found}` - Sandbox ID not found (when using a string ID)
  * `{:error, reason}` - Database or other failure
  """
  @spec schedule_sandbox_deletion(Project.t() | Ecto.UUID.t(), User.t()) ::
          {:ok, Project.t()} | {:error, :unauthorized | :not_found | term()}
  def schedule_sandbox_deletion(%Project{} = sandbox, %User{} = actor) do
    if Permissions.can?(:sandboxes, :delete_sandbox, actor, sandbox) do
      do_schedule_sandbox_deletion(sandbox)
    else
      {:error, :unauthorized}
    end
  end

  def schedule_sandbox_deletion(sandbox_id, %User{} = actor)
      when is_binary(sandbox_id) do
    case Lightning.Projects.get_project(sandbox_id) do
      %Project{} = sandbox -> schedule_sandbox_deletion(sandbox, actor)
      nil -> {:error, :not_found}
    end
  end

  @doc """
  Clears the scheduled deletion on a sandbox subtree, restoring it to active use.

  Walks every descendant of `sandbox` and clears `scheduled_deletion` on any
  row that has it set. Triggers are not automatically re-enabled: this is an
  admin recovery path and the operator decides whether the subtree should
  resume firing triggers.

  ## Cascade semantics

  The cancel clears `scheduled_deletion` on every descendant that has it set,
  regardless of whether the schedule originated from this subtree's parent
  or from a separate scheduling action on the descendant itself. Any row
  whose `scheduled_deletion` is already nil is left alone.

  ## Limit

  Restoring a sandbox moves it back into the active count, so the same
  usage-limit action that gates new sandbox creation also gates restore.
  When the active-sandbox count is already at the limit, restore is
  refused with `{:error, :too_many_sandboxes, message}`; the operator
  needs to delete an active sandbox first.

  ## Parameters
  * `sandbox` - Sandbox project to restore (or sandbox ID as string)
  * `actor` - User performing the action (needs `:delete_sandbox` permission)

  ## Returns
  * `{:ok, restored_sandbox}` - Sandbox subtree restored
  * `{:error, :unauthorized}` - Actor lacks permission on the sandbox
  * `{:error, :not_found}` - Sandbox ID not found (when using a string ID)
  * `Lightning.Extensions.UsageLimiting.error()` - Limit reached
  """
  @spec cancel_scheduled_sandbox_deletion(
          Project.t() | Ecto.UUID.t(),
          User.t()
        ) ::
          {:ok, Project.t()}
          | {:error, :unauthorized | :not_found | term()}
          | Lightning.Extensions.UsageLimiting.error()
  def cancel_scheduled_sandbox_deletion(%Project{} = sandbox, %User{} = actor) do
    if Permissions.can?(:sandboxes, :delete_sandbox, actor, sandbox) do
      case ProjectLimiter.limit_new_sandbox(sandbox.id) do
        :ok -> do_cancel_scheduled_sandbox_deletion(sandbox)
        {:error, _reason, _message} = error -> error
      end
    else
      {:error, :unauthorized}
    end
  end

  def cancel_scheduled_sandbox_deletion(sandbox_id, %User{} = actor)
      when is_binary(sandbox_id) do
    case Lightning.Projects.get_project(sandbox_id) do
      %Project{} = sandbox -> cancel_scheduled_sandbox_deletion(sandbox, actor)
      nil -> {:error, :not_found}
    end
  end

  defp do_schedule_sandbox_deletion(%Project{} = sandbox) do
    date = scheduled_deletion_date()
    subtree_ids = subtree_ids(sandbox)

    Repo.transact(fn ->
      {_count, _} =
        Repo.update_all(
          from(p in Project, where: p.id in ^subtree_ids),
          set: [scheduled_deletion: date]
        )

      {_count, _} =
        Repo.update_all(
          from(t in Trigger,
            join: w in assoc(t, :workflow),
            where: w.project_id in ^subtree_ids and t.enabled == true
          ),
          set: [enabled: false]
        )

      SandboxPromExPlugin.fire_sandbox_scheduled_for_deletion_event()

      {:ok, %{sandbox | scheduled_deletion: date}}
    end)
  end

  defp do_cancel_scheduled_sandbox_deletion(%Project{} = sandbox) do
    subtree_ids = subtree_ids(sandbox)

    {_count, _} =
      Repo.update_all(
        from(p in Project,
          where: p.id in ^subtree_ids and not is_nil(p.scheduled_deletion)
        ),
        set: [scheduled_deletion: nil]
      )

    SandboxPromExPlugin.fire_sandbox_deletion_cancelled_event()

    {:ok, %{sandbox | scheduled_deletion: nil}}
  end

  defp subtree_ids(%Project{id: id}) do
    descendant_ids =
      [id]
      |> Lightning.Projects.descendants_query()
      |> Repo.all()

    [id | descendant_ids]
  end

  defp scheduled_deletion_date do
    case Lightning.Config.purge_deleted_after_days() do
      nil -> DateTime.utc_now()
      integer -> DateTime.utc_now() |> Timex.shift(days: integer)
    end
    |> DateTime.truncate(:second)
  end

  defp create_sandbox_from_parent(parent, actor, attrs) do
    sandbox_name = Map.fetch!(attrs, :name)
    sandbox_color = Map.get(attrs, :color)
    sandbox_env = Map.get(attrs, :env)

    Repo.transaction(fn ->
      if nesting_depth_exceeded?(parent) do
        Repo.rollback(:nesting_too_deep)
      end

      parent_with_data = load_parent_associations(parent)

      sandbox_attrs =
        build_sandbox_project_attributes(
          parent_with_data,
          actor,
          sandbox_name,
          sandbox_color,
          sandbox_env
        )

      case create_empty_sandbox(parent_with_data, sandbox_attrs) do
        {:ok, sandbox} ->
          sandbox
          |> Repo.preload(:project_users)
          |> clone_credentials_from_parent(parent_with_data)
          |> clone_keychains_from_parent(parent_with_data, actor)
          |> clone_workflows_from_parent(parent_with_data)
          |> finalize_sandbox_setup(parent_with_data, attrs)

        {:error, changeset} ->
          Repo.rollback(changeset)
      end
    end)
    |> case do
      {:ok, project} ->
        SandboxPromExPlugin.fire_sandbox_created_event()
        {:ok, project}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  defp load_parent_associations(parent) do
    Repo.preload(parent,
      workflows: [
        jobs: [:project_credential, :keychain_credential],
        triggers: [:webhook_auth_methods],
        edges: []
      ],
      project_credentials: [:credential],
      project_users: []
    )
  end

  defp build_sandbox_project_attributes(parent, actor, name, color, env) do
    owner_membership = %{user_id: actor.id, role: :owner}

    additional_memberships =
      parent.project_users
      |> Enum.reject(&(&1.user_id == actor.id))
      |> Enum.map(fn pu ->
        role = if pu.role == :owner, do: :admin, else: pu.role
        %{user_id: pu.user_id, role: role}
      end)

    parent
    |> Map.take(@cloned_project_fields)
    |> Map.merge(%{
      name: name,
      color: color,
      env: env,
      project_users: [owner_membership | additional_memberships]
    })
  end

  defp create_empty_sandbox(parent, attrs) do
    Lightning.Projects.create_sandbox(parent, attrs, false)
  end

  defp clone_credentials_from_parent(sandbox, parent) do
    current_time = DateTime.utc_now() |> DateTime.truncate(:second)

    credential_rows =
      Enum.map(parent.project_credentials, fn parent_credential ->
        %{
          project_id: sandbox.id,
          credential_id: parent_credential.credential_id,
          inserted_at: current_time,
          updated_at: current_time
        }
      end)

    {_, inserted_credentials} =
      Repo.insert_all(ProjectCredential, credential_rows,
        on_conflict: :nothing,
        returning: [:id, :credential_id]
      )

    credential_id_mapping =
      Map.new(inserted_credentials, &{&1.credential_id, &1.id})

    Map.put(sandbox, :credential_id_mapping, credential_id_mapping)
  end

  defp clone_keychains_from_parent(sandbox, parent, actor) do
    used_keychains = collect_keychains_used_by_parent_jobs(parent)

    keychain_id_mapping =
      Enum.reduce(used_keychains, %{}, fn original_keychain, mapping ->
        cloned_keychain =
          create_or_find_keychain_in_sandbox(original_keychain, sandbox, actor)

        Map.put(mapping, original_keychain.id, cloned_keychain.id)
      end)

    Map.put(sandbox, :keychain_id_mapping, keychain_id_mapping)
  end

  defp collect_keychains_used_by_parent_jobs(parent) do
    parent.workflows
    |> Enum.flat_map(& &1.jobs)
    |> Enum.map(& &1.keychain_credential)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq_by(& &1.id)
  end

  defp create_or_find_keychain_in_sandbox(original_keychain, sandbox, actor) do
    Repo.get_by(KeychainCredential,
      project_id: sandbox.id,
      name: original_keychain.name
    ) ||
      create_keychain_in_sandbox(original_keychain, sandbox, actor)
  end

  defp create_keychain_in_sandbox(original_keychain, sandbox, actor) do
    # The project must be on the base struct so that
    # validate_default_credential_belongs_to_project can see it when
    # changeset/2 runs; put_assoc after the fact would skip the check.
    %KeychainCredential{
      project: sandbox,
      project_id: sandbox.id,
      created_by_id: actor.id
    }
    |> KeychainCredential.changeset(%{
      name: original_keychain.name,
      path: original_keychain.path,
      default_credential_id: original_keychain.default_credential_id
    })
    |> Repo.insert!()
  end

  defp clone_workflows_from_parent(sandbox, parent) do
    workflow_id_mapping = create_sandbox_workflows(parent, sandbox)

    updated_sandbox =
      sandbox
      |> Map.put(:workflow_id_mapping, workflow_id_mapping)

    job_id_mapping =
      clone_jobs_with_updated_references(
        parent,
        updated_sandbox.workflow_id_mapping,
        updated_sandbox.credential_id_mapping,
        updated_sandbox.keychain_id_mapping
      )

    trigger_id_mapping =
      clone_triggers_with_disabled_state(parent, workflow_id_mapping)

    updated_sandbox
    |> Map.put(:job_id_mapping, job_id_mapping)
    |> Map.put(:trigger_id_mapping, trigger_id_mapping)
    |> clone_workflow_edges(parent)
    |> update_node_positions(parent)
  end

  defp create_sandbox_workflows(parent, sandbox) do
    Enum.reduce(parent.workflows, %{}, fn parent_workflow, mapping ->
      {:ok, _} = WorkflowVersions.ensure_version_recorded(parent_workflow)

      {:ok, sandbox_workflow} =
        %Workflow{}
        |> Workflow.changeset(%{
          name: parent_workflow.name,
          project_id: sandbox.id,
          concurrency: parent_workflow.concurrency,
          enable_job_logs: parent_workflow.enable_job_logs,
          positions: %{}
        })
        |> Repo.insert()

      Map.put(mapping, parent_workflow.id, sandbox_workflow.id)
    end)
  end

  defp clone_jobs_with_updated_references(
         parent,
         workflow_id_mapping,
         credential_id_mapping,
         keychain_id_mapping
       ) do
    parent.workflows
    |> Enum.flat_map(
      &clone_jobs_for_workflow(
        &1,
        workflow_id_mapping,
        credential_id_mapping,
        keychain_id_mapping
      )
    )
    |> Map.new()
  end

  defp clone_jobs_for_workflow(
         parent_workflow,
         workflow_id_mapping,
         credential_id_mapping,
         keychain_id_mapping
       ) do
    sandbox_workflow_id = Map.fetch!(workflow_id_mapping, parent_workflow.id)

    Enum.map(parent_workflow.jobs, fn parent_job ->
      sandbox_keychain_id =
        get_sandbox_keychain_id(parent_job, keychain_id_mapping)

      sandbox_credential_id =
        get_sandbox_credential_id(
          parent_job,
          sandbox_keychain_id,
          credential_id_mapping
        )

      sandbox_job =
        parent_job
        |> build_job_attributes(
          sandbox_workflow_id,
          sandbox_credential_id,
          sandbox_keychain_id
        )
        |> create_sandbox_job()

      {parent_job.id, sandbox_job.id}
    end)
  end

  defp clone_triggers_with_disabled_state(parent, workflow_id_mapping) do
    parent.workflows
    |> Enum.flat_map(fn parent_workflow ->
      sandbox_workflow_id = Map.fetch!(workflow_id_mapping, parent_workflow.id)

      Enum.map(parent_workflow.triggers, fn parent_trigger ->
        sandbox_trigger_attrs = %{
          id: Ecto.UUID.generate(),
          workflow_id: sandbox_workflow_id,
          type: parent_trigger.type,
          enabled: false,
          comment: parent_trigger.comment,
          custom_path: parent_trigger.custom_path,
          cron_expression: parent_trigger.cron_expression,
          kafka_configuration:
            case parent_trigger.kafka_configuration do
              %_{} = config -> Map.from_struct(config)
              other -> other
            end
        }

        {:ok, sandbox_trigger} =
          %Trigger{}
          |> Trigger.changeset(sandbox_trigger_attrs)
          |> Repo.insert()

        if parent_trigger.webhook_auth_methods &&
             parent_trigger.webhook_auth_methods != [] do
          sandbox_trigger
          |> Repo.preload(:webhook_auth_methods)
          |> Ecto.Changeset.change()
          |> Ecto.Changeset.put_assoc(
            :webhook_auth_methods,
            parent_trigger.webhook_auth_methods
          )
          |> Repo.update!()
        end

        {parent_trigger.id, sandbox_trigger.id}
      end)
    end)
    |> Map.new()
  end

  defp clone_workflow_edges(sandbox, parent) do
    Enum.each(parent.workflows, fn parent_workflow ->
      sandbox_workflow_id =
        Map.fetch!(sandbox.workflow_id_mapping, parent_workflow.id)

      Enum.each(parent_workflow.edges, fn parent_edge ->
        %Edge{}
        |> Edge.changeset(%{
          id: Ecto.UUID.generate(),
          workflow_id: sandbox_workflow_id,
          condition_type: parent_edge.condition_type,
          condition_expression: parent_edge.condition_expression,
          condition_label: parent_edge.condition_label,
          enabled: parent_edge.enabled,
          source_job_id:
            parent_edge.source_job_id &&
              Map.fetch!(sandbox.job_id_mapping, parent_edge.source_job_id),
          source_trigger_id:
            parent_edge.source_trigger_id &&
              Map.fetch!(
                sandbox.trigger_id_mapping,
                parent_edge.source_trigger_id
              ),
          target_job_id:
            parent_edge.target_job_id &&
              Map.fetch!(sandbox.job_id_mapping, parent_edge.target_job_id)
        })
        |> Repo.insert!()
      end)
    end)

    sandbox
  end

  defp update_node_positions(sandbox, parent) do
    Enum.each(parent.workflows, fn parent_workflow ->
      sandbox_workflow_id =
        Map.fetch!(sandbox.workflow_id_mapping, parent_workflow.id)

      parent_job_ids = Enum.map(parent_workflow.jobs, & &1.id)
      parent_trigger_ids = Enum.map(parent_workflow.triggers, & &1.id)

      combined_id_mapping =
        Map.merge(
          Map.take(sandbox.job_id_mapping, parent_job_ids),
          Map.take(sandbox.trigger_id_mapping, parent_trigger_ids)
        )

      updated_positions =
        remap_node_positions(
          parent_workflow.positions || %{},
          combined_id_mapping
        )

      Repo.get!(Workflow, sandbox_workflow_id)
      |> Ecto.Changeset.change(positions: updated_positions)
      |> Repo.update!()
    end)

    sandbox
  end

  defp finalize_sandbox_setup(sandbox, parent, original_attrs) do
    sandbox
    |> copy_workflow_version_history(sandbox.workflow_id_mapping)
    |> create_initial_workflow_snapshots()
    |> copy_selected_dataclips(parent.id, Map.get(original_attrs, :dataclip_ids))
    |> clone_collections_from_parent(parent)
  end

  defp clone_collections_from_parent(sandbox, parent) do
    parent_names = parent |> Collections.list_project_collections() |> names()
    insert_empty_collections(sandbox.id, parent_names)
    sandbox
  end

  @doc """
  Synchronises collection names from a sandbox to its merge target.

  Names only in the source are created empty in the target; names only in
  the target are deleted along with their items. Collection data is never
  copied. The combined byte-size of deleted collections is reported via
  `CollectionHook.handle_delete/2` for usage accounting.

  Runs inside a single transaction.

  ## Options

    * `:allow_deletions` - when `true`, target-only collections (and their items)
      are deleted so the target matches the source. Defaults to `false`: callers
      must opt in. The merge path opts in only when the actor holds
      `:manage_collection`, so an editor merge never prunes target collections.
  """
  @spec sync_collections(Project.t(), Project.t(), keyword()) ::
          {:ok, %{created: non_neg_integer(), deleted: non_neg_integer()}}
          | {:error, term()}
  def sync_collections(%Project{} = source, %Project{} = target, opts \\ []) do
    allow_deletions? = Keyword.get(opts, :allow_deletions, false)

    source_names = source |> Collections.list_project_collections() |> names()

    target_collections = Collections.list_project_collections(target)
    target_names = names(target_collections)

    to_create = MapSet.difference(source_names, target_names)

    collections_to_delete =
      if allow_deletions? do
        names_to_delete = MapSet.difference(target_names, source_names)
        Enum.filter(target_collections, &(&1.name in names_to_delete))
      else
        []
      end

    to_delete_ids = Enum.map(collections_to_delete, & &1.id)

    deleted_byte_size =
      Enum.reduce(collections_to_delete, 0, &(&1.byte_size_sum + &2))

    Repo.transaction(fn ->
      {created, _} = insert_empty_collections(target.id, to_create)
      {deleted, _} = delete_collections(to_delete_ids)

      if deleted_byte_size > 0 do
        :ok = CollectionHook.handle_delete(target.id, deleted_byte_size)
      end

      %{created: created, deleted: deleted}
    end)
  end

  defp names(collections), do: MapSet.new(collections, & &1.name)

  defp insert_empty_collections(project_id, names) do
    if Enum.empty?(names) do
      {0, nil}
    else
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      rows =
        Enum.map(names, fn name ->
          %{
            id: Ecto.UUID.generate(),
            name: name,
            project_id: project_id,
            byte_size_sum: 0,
            inserted_at: now,
            updated_at: now
          }
        end)

      # Concurrent merges may race to create the same collection.
      Repo.insert_all(Collection, rows, on_conflict: :nothing)
    end
  end

  defp delete_collections([]), do: {0, nil}

  defp delete_collections(ids) do
    Repo.delete_all(from c in Collection, where: c.id in ^ids)
  end

  defp copy_workflow_version_history(sandbox, workflow_id_mapping) do
    latest_versions =
      from(version in WorkflowVersion,
        where: version.workflow_id in ^Map.keys(workflow_id_mapping),
        distinct: version.workflow_id,
        order_by: [
          asc: version.workflow_id,
          desc: version.inserted_at,
          desc: version.id
        ],
        select: %{
          workflow_id: version.workflow_id,
          hash: version.hash,
          source: version.source
        }
      )
      |> Repo.all()

    Enum.each(latest_versions, fn %{
                                    workflow_id: parent_workflow_id,
                                    hash: version_hash,
                                    source: version_source
                                  } ->
      Repo.insert!(%WorkflowVersion{
        workflow_id: Map.fetch!(workflow_id_mapping, parent_workflow_id),
        hash: version_hash,
        source: version_source
      })
    end)

    sandbox
  end

  defp create_initial_workflow_snapshots(sandbox) do
    sandbox_workflow_ids = Map.values(sandbox.workflow_id_mapping)

    Enum.each(sandbox_workflow_ids, fn workflow_id ->
      Lightning.Workflows.Workflow
      |> Repo.get!(workflow_id)
      |> Workflows.maybe_create_latest_snapshot()
    end)

    sandbox
  end

  defp copy_selected_dataclips(sandbox, _parent_id, nil), do: sandbox
  defp copy_selected_dataclips(sandbox, _parent_id, []), do: sandbox

  defp copy_selected_dataclips(sandbox, parent_id, dataclip_ids)
       when is_list(dataclip_ids) do
    selected_dataclips =
      from(dataclip in Lightning.Invocation.Dataclip,
        where:
          dataclip.project_id == ^parent_id and
            dataclip.id in ^dataclip_ids and
            dataclip.type in ^@allowed_dataclip_types and
            not is_nil(dataclip.name),
        select: %{
          name: dataclip.name,
          body: type(dataclip.body, :map),
          type: dataclip.type
        }
      )
      |> Repo.all()

    Enum.each(selected_dataclips, fn dataclip_attrs ->
      dataclip_attrs
      |> Map.put(:project_id, sandbox.id)
      |> Lightning.Invocation.Dataclip.new()
      |> Repo.insert!()
    end)

    sandbox
  end

  defp get_sandbox_keychain_id(
         %{keychain_credential: %KeychainCredential{id: parent_keychain_id}},
         keychain_id_mapping
       ) do
    Map.get(keychain_id_mapping, parent_keychain_id)
  end

  defp get_sandbox_keychain_id(_job, _keychain_id_mapping), do: nil

  defp get_sandbox_credential_id(
         _job,
         sandbox_keychain_id,
         _credential_id_mapping
       )
       when not is_nil(sandbox_keychain_id) do
    nil
  end

  defp get_sandbox_credential_id(
         %{project_credential: %ProjectCredential{credential_id: credential_id}},
         nil,
         credential_id_mapping
       ) do
    Map.get(credential_id_mapping, credential_id)
  end

  defp get_sandbox_credential_id(
         _job,
         _sandbox_keychain_id,
         _credential_id_mapping
       ),
       do: nil

  defp build_job_attributes(
         parent_job,
         sandbox_workflow_id,
         sandbox_credential_id,
         sandbox_keychain_id
       ) do
    %{
      id: Ecto.UUID.generate(),
      name: parent_job.name,
      body: parent_job.body,
      adaptor: parent_job.adaptor,
      workflow_id: sandbox_workflow_id,
      project_credential_id: sandbox_credential_id,
      keychain_credential_id: sandbox_keychain_id
    }
  end

  defp create_sandbox_job(job_attrs) do
    %Job{} |> Job.changeset(job_attrs) |> Repo.insert!()
  end

  defp remap_node_positions(parent_positions, id_mapping)
       when is_map(parent_positions) do
    parent_positions
    |> Enum.reduce(%{}, fn {parent_node_id, coordinates}, updated_positions ->
      case Map.get(id_mapping, parent_node_id) do
        nil ->
          updated_positions

        sandbox_node_id ->
          Map.put(updated_positions, sandbox_node_id, coordinates)
      end
    end)
    |> case do
      empty_map when map_size(empty_map) == 0 -> nil
      positions_map -> positions_map
    end
  end
end
