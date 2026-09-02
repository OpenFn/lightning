defmodule Lightning.Workflows do
  @moduledoc """
  The Workflows context.
  """

  use Oban.Worker,
    queue: :background,
    max_attempts: 1

  import Ecto.Query

  alias Ecto.Multi

  alias Lightning.Config
  alias Lightning.Credentials.Scoping
  alias Lightning.Projects.Project
  alias Lightning.Repo
  alias Lightning.Workflows.Audit
  alias Lightning.Workflows.Edge
  alias Lightning.Workflows.Events
  alias Lightning.Workflows.Job
  alias Lightning.Workflows.Query
  alias Lightning.Workflows.Snapshot
  alias Lightning.Workflows.Trigger
  alias Lightning.Workflows.Workflow
  alias Lightning.WorkflowVersions
  alias Lightning.WorkOrder

  defdelegate subscribe(project_id), to: Events

  require Logger

  @doc """
  Returns the list of workflows.

  ## Examples

      iex> list_workflows()
      [%Workflow{}, ...]

  """
  def list_workflows do
    Repo.all(Workflow)
  end

  @doc """
  Returns the list of workflows for a project.

  ## Examples

      iex> list_project_workflows(project_id)
      [%Workflow{}, ...]

  """
  def list_project_workflows(project_id, opts \\ []) do
    include = Keyword.get(opts, :include, [])

    from(w in Workflow,
      where: w.project_id == ^project_id,
      preload: ^include,
      order_by: :name
    )
    |> Repo.all()
  end

  @spec project_workflows_using_credentials([
          project_credential :: Ecto.UUID.t(),
          ...
        ]) ::
          %{
            optional(project :: Ecto.UUID.t()) => [
              workflow_name :: binary(),
              ...
            ]
          }
  def project_workflows_using_credentials(project_credential_ids) do
    query =
      from w in Workflow,
        join: j in assoc(w, :jobs),
        where: j.project_credential_id in ^project_credential_ids,
        select: %{name: w.name, project_id: w.project_id},
        distinct: true,
        order_by: w.name

    query
    |> Repo.all()
    |> Enum.group_by(& &1.project_id, & &1.name)
  end

  @doc """
  Gets a single workflow with optional preloads.

  Raises `Ecto.NoResultsError` if the Workflow does not exist.

  ## Examples

      iex> get_workflow!(123)
      %Workflow{}

      iex> get_workflow!(456)
      ** (Ecto.NoResultsError)

      iex> get_workflow!(123, include: [:triggers])
      %Workflow{triggers: [...]}

  """
  def get_workflow!(id, opts \\ []) do
    get_workflow_query(id, opts) |> Repo.one!()
  end

  @doc """
  Gets a single workflow with optional preloads, returns `nil` if not found.

  ## Examples

      iex> get_workflow(123)
      %Workflow{}

      iex> get_workflow(456)
      nil

      iex> get_workflow(123, include: [:triggers])
      %Workflow{triggers: [...]}

  """
  def get_workflow(id, opts \\ []) do
    get_workflow_query(id, opts) |> Repo.one()
  end

  defp get_workflow_query(id, opts) do
    include = Keyword.get(opts, :include, [])

    Workflow
    |> where(id: ^id)
    |> preload(^include)
  end

  @doc """
  Gets a workflow by id, scoped to the given project.

  Returns `nil` when the id is malformed, missing, belongs to another project,
  or is marked for deletion, so it can't be used to read or mutate a workflow
  across projects or one on its way out.
  """
  def get_workflow_for_project(%Project{} = project, id, opts \\ []) do
    if Lightning.Validators.valid_uuid?(id) do
      from(w in Query.workflows_for(project), where: w.id == ^id)
      |> preload(^Keyword.get(opts, :include, []))
      |> Repo.one()
    end
  end

  @spec save_workflow(
          Ecto.Changeset.t(Workflow.t()) | map(),
          struct(),
          keyword()
        ) ::
          {:ok, Workflow.t()}
          | {:error,
             Ecto.Changeset.t(Workflow.t())
             | :workflow_deleted
             | :snapshot_failed}
  def save_workflow(changeset_or_attrs, actor, opts \\ [])

  def save_workflow(
        %Ecto.Changeset{data: %Workflow{}} = changeset,
        actor,
        opts
      ) do
    skip_reconcile = Keyword.get(opts, :skip_reconcile, false)

    # Only the transaction is guarded. Post-commit side effects run OUTSIDE the
    # rescue: once Repo.transaction has returned {:ok, _}, the write is durable
    # and must never be rewritten into {:error, _}.
    transaction_result =
      try do
        changeset
        |> build_save_multi(actor)
        |> Repo.transaction()

        # NOTE: Ecto.StaleEntryError is deliberately NOT caught — optimistic
        # lock conflicts have their own reload UX and workflows_test.exs asserts
        # it raises. Anything off this allow-list re-raises automatically with
        # the original stacktrace.
      rescue
        e in Ecto.ChangeError ->
          # Malformed values that pass cast but fail at dump (e.g. a 16-byte
          # non-hex :binary_id). Convert to a field-targeted changeset so the
          # collaborative session and LiveView editor surface a toast instead of
          # crashing the GenServer.
          {:error, :rescued,
           rescued_changeset(
             changeset,
             {:warning,
              "save_workflow rescued Ecto.ChangeError: #{Exception.message(e)}"},
             "contains an invalid reference or value"
           )}

        e in Ecto.Query.CastError ->
          # Query-time cast failures (e.g. a malformed :binary_id reaching a
          # Repo query). Convert to a field-targeted changeset so the
          # collaborative session and LiveView editor surface a toast instead of
          # crashing the GenServer.
          {:error, :rescued,
           rescued_changeset(
             changeset,
             {:warning,
              "save_workflow rescued Ecto.Query.CastError: #{Exception.message(e)}"},
             "contains an invalid value"
           )}

        e in Ecto.ConstraintError ->
          # An UNDECLARED DB constraint that Ecto did not map to a changeset
          # error because the changeset declares no matching unique/foreign_key
          # constraint — e.g. the workflows_pkey duplicate INSERT (#4830;
          # Workflow declares no unique_constraint(:id)). Convert to a changeset
          # error instead of crashing the session.
          {:error, :rescued, constraint_error_changeset(changeset, e)}
      end

    handle_save_result(transaction_result, changeset, skip_reconcile)
  end

  def save_workflow(%{} = attrs, actor, opts) do
    Workflow.changeset(%Workflow{}, attrs)
    |> save_workflow(actor, opts)
  end

  @doc """
  Returns a workflow name that is unique within the given project, derived
  from `base_name`. A blank or nil `base_name` defaults to
  "Untitled workflow". On collision, appends " 1", " 2", etc. until a free
  name is found.

  The check includes soft-deleted rows because the unique index on
  `[:name, :project_id]` is not partial. (Delete paths rename workflows to
  `<name>_del` via `soft_delete_changeset/1`, so in practice deletion frees
  the original name — but any row still occupying a name must be avoided.)

  Note: this is check-then-insert, so two concurrent saves can still compute
  the same name and one will lose on the unique constraint. Callers already
  handle that `{:error, changeset}`; no retry is attempted here.

  ## Options

  * `:exclude_workflow_id` - a workflow id whose current name should not
    count as a clash. Pass the workflow being renamed/edited so its own
    name doesn't get " 1" appended on every save.
  """
  @spec unique_workflow_name(String.t() | nil, Ecto.UUID.t(), keyword()) ::
          String.t()
  def unique_workflow_name(base_name, project_id, opts \\ []) do
    exclude_workflow_id = Keyword.get(opts, :exclude_workflow_id)

    base_name =
      base_name
      |> to_string()
      |> String.trim()
      |> case do
        "" -> "Untitled workflow"
        name -> name
      end

    existing_names =
      from(w in Workflow,
        where: w.project_id == ^project_id,
        select: w.name
      )
      |> then(fn query ->
        if exclude_workflow_id do
          from(w in query, where: w.id != ^exclude_workflow_id)
        else
          query
        end
      end)
      |> Repo.all()
      |> MapSet.new()

    if MapSet.member?(existing_names, base_name) do
      1
      |> Stream.iterate(&(&1 + 1))
      |> Stream.map(&"#{base_name} #{&1}")
      |> Enum.find(&(not MapSet.member?(existing_names, &1)))
    else
      base_name
    end
  end

  # Builds the Ecto.Multi pipeline for save_workflow. Does NOT call
  # Repo.transaction — that stays in the try/rescue block of the caller so
  # rescue wraps only the transaction, not this builder.
  defp build_save_multi(changeset, actor) do
    Multi.new()
    |> Multi.put(:actor, actor)
    |> Multi.run(:validate, fn _repo, _changes ->
      validate_not_deleted(changeset)
    end)
    |> Multi.run(:orphan_deleted_jobs, fn repo, _changes ->
      orphan_jobs_being_deleted(repo, changeset)
    end)
    |> Multi.insert_or_update(:workflow, changeset)
    |> Multi.run(:credential_scope_check, fn _repo, %{workflow: workflow} ->
      credential_scope_check(workflow, changeset)
    end)
    |> Multi.run(:cleanup_orphaned_edges, fn repo,
                                             %{
                                               workflow: workflow,
                                               orphan_deleted_jobs:
                                                 orphaned_edge_ids
                                             } ->
      cleanup_orphaned_edges(repo, workflow.id, orphaned_edge_ids)
    end)
    |> maybe_capture_snapshot(changeset)
    |> maybe_audit_workflow_state_changes(changeset)
    |> Multi.run(:workflow_version, fn _repo, %{workflow: workflow} ->
      hash = WorkflowVersions.generate_hash(workflow)
      WorkflowVersions.record_version(workflow, hash)
    end)
  end

  defp validate_not_deleted(%{data: %{deleted_at: nil}}), do: {:ok, true}
  defp validate_not_deleted(_changeset), do: {:error, :workflow_deleted}

  # Read-your-writes: the just-written jobs of this workflow. Every save path
  # funnels through here, so this is the single chokepoint that rejects a job
  # referencing a credential owned by a different project than the workflow's.
  defp credential_scope_check(workflow, changeset) do
    jobs = Scoping.job_refs_for_workflow(workflow.id)

    case Scoping.out_of_project_references(workflow.project_id, jobs) do
      [] ->
        {:ok, :ok}

      violations ->
        {:error, apply_violations_to_changeset(changeset, violations, jobs)}
    end
  end

  # A violation on a job carried in this change surfaces as a field error on
  # its nested changeset. A violation on a persisted job the change never
  # touched (legacy poisoned data) has no changeset to carry it, so it becomes
  # a base error naming the job — the save still fails, diagnosably.
  defp apply_violations_to_changeset(changeset, violations, refs) do
    {changeset, unattached} =
      case Ecto.Changeset.get_change(changeset, :jobs) do
        nil ->
          {changeset, violations}

        job_changesets ->
          {jobs, unattached} =
            Scoping.attach_violations(
              job_changesets,
              violations,
              &Ecto.Changeset.get_field(&1, :id)
            )

          {Ecto.Changeset.put_change(changeset, :jobs, jobs), unattached}
      end

    descriptions =
      Map.new(refs, fn %{key: id, label: name} -> {id, ~s(job "#{name}")} end)

    Scoping.invalidate(changeset, unattached, descriptions)
  end

  defp maybe_capture_snapshot(multi, %{changes: changes}) when changes == %{},
    do: multi

  defp maybe_capture_snapshot(multi, _changeset), do: capture_snapshot(multi)

  # Dispatches the Repo.transaction result to the appropriate outcome. The
  # {:ok, ...} head runs OUTSIDE the rescue block — after_commit's return is
  # intentionally discarded so that a side-effect failure never downgrades a
  # durable {:ok} save into {:error, _}.
  defp handle_save_result(
         {:ok, %{workflow: workflow}},
         changeset,
         skip_reconcile
       ) do
    after_commit(workflow, changeset, skip_reconcile)
    {:ok, workflow}
  end

  defp handle_save_result({:error, :rescued, changeset}, _changeset, _skip),
    do: {:error, changeset}

  defp handle_save_result(
         {:error, :workflow, changeset, _changes},
         _changeset,
         _skip
       ),
       do: {:error, changeset}

  defp handle_save_result(
         {:error, :snapshot, snapshot_changeset, %{workflow: workflow}},
         _changeset,
         _skip
       ) do
    Logger.warning(fn ->
      """
      Failed to save snapshot for workflow: #{workflow.id}
      #{inspect(snapshot_changeset.errors)}
      """
    end)

    {:error, :snapshot_failed}
  end

  defp handle_save_result(
         {:error, _action, reason, _changes},
         _changeset,
         _skip
       ),
       do: {:error, reason}

  # Post-commit side effects: workflow_updated broadcast,
  # telemetry, and optional reconciliation. Runs OUTSIDE the rescue block: the
  # write is already durable, so these MUST NOT raise the rescued Ecto types
  # (they operate on already-validated/committed data) — a raise here is an honest
  # crash, never a downgrade of a committed save. If you add a post-commit step
  # that can fail, handle it here; don't widen the rescue to cover it.
  defp after_commit(workflow, changeset, skip_reconcile) do
    Events.workflow_updated(workflow)

    fire_workflow_saved_telemetry(workflow)

    # Reconcile changes with active collaborative editing sessions.
    # Skip reconciliation when changes originate from a collaborative session
    # to prevent circular updates (Session → DB → Session).
    unless skip_reconcile do
      Lightning.Collaboration.WorkflowReconciler.reconcile_workflow_changes(
        changeset,
        workflow
      )
    end
  end

  defp fire_workflow_saved_telemetry(workflow) do
    # Emit telemetry for workflow save metrics
    is_sandbox =
      Lightning.Repo.get(Lightning.Projects.Project, workflow.project_id)
      |> Lightning.Projects.Project.sandbox?()

    Lightning.Projects.SandboxPromExPlugin.fire_workflow_saved_event(is_sandbox)
  end

  # Single home for "convert a rescued exception into a :base changeset error so
  # the collaborative session (session.ex) and workflow channel render a toast
  # instead of crashing". Callers supply the log level + message and the
  # user-facing :base message. We cannot reliably map a nested job/edge/trigger id
  # back to its association path, so the error is attached to :base. (Field
  # coverage that pre-empts this is a follow-up.)
  defp rescued_changeset(changeset, {level, log_message}, base_message)
       when level in [:warning, :error] do
    Logger.log(level, log_message)

    changeset
    |> Ecto.Changeset.add_error(:base, base_message)
    |> Map.put(:action, derive_action(changeset))
  end

  # Derive the changeset action from the data's persistence state so the rescued
  # changeset reports :insert on the attrs/new-workflow path (e.g. the #4830
  # duplicate-pkey INSERT) and :update on the existing-workflow path.
  defp derive_action(%Ecto.Changeset{data: %{__meta__: %{state: :built}}}),
    do: :insert

  defp derive_action(_changeset), do: :update

  # Undeclared constraint (e.g. workflows_pkey duplicate, #4830). We cannot
  # reliably map the PG constraint name back to a nested association path, so
  # attach a generic message to :base and log the detail. Declared constraints
  # never reach here — Ecto converts those to changeset errors that return via
  # the normal Multi path. The raw constraint name is logged but never leaked
  # into the user-facing message.
  #
  # A constraint physically defined on the `workflows` table is workflow-owned
  # (e.g. the duplicate-pkey case #4830, or any future workflows_* unique/FK) and
  # logs at :warning. Anything else is a non-workflow side-table failure
  # (workflow_snapshots_*, workflow_versions_*, audit_*) mislabelled to the user as
  # a workflow error, so it logs at :error for triage while still converting to a
  # changeset (never crashes the session — see #4816). A nil constraint is not a
  # binary, so it takes the safe :error branch.
  defp constraint_error_changeset(changeset, %Ecto.ConstraintError{} = e) do
    {level, log_message} =
      if is_binary(e.constraint) and
           String.starts_with?(e.constraint, "workflows_") do
        {:warning,
         "save_workflow rescued workflow Ecto.ConstraintError " <>
           "(type=#{inspect(e.type)}, constraint=#{inspect(e.constraint)})"}
      else
        {:error,
         "save_workflow rescued a NON-workflow Ecto.ConstraintError — likely a " <>
           "snapshot/audit/version side-effect, mislabelled to the user as a " <>
           "workflow error (type=#{inspect(e.type)}, constraint=#{inspect(e.constraint)})"}
      end

    rescued_changeset(
      changeset,
      {level, log_message},
      "could not be saved due to a conflicting or missing reference"
    )
  end

  # Nullifies edge FK references to jobs that are about to be deleted.
  # This prevents PostgreSQL's cascade delete from removing edges that Ecto
  # is trying to update (the retargeting race condition).
  #
  # Returns the IDs of edges whose target_job_id or source_job_id was nullified,
  # so that cleanup_orphaned_edges can precisely remove only those edges (if they
  # weren't retargeted by the changeset).
  defp orphan_jobs_being_deleted(repo, changeset) do
    deleted_job_ids =
      changeset
      |> Ecto.Changeset.get_change(:jobs, [])
      |> Enum.filter(fn cs -> cs.action in [:replace, :delete] end)
      |> Enum.map(fn cs -> cs.data.id end)

    if deleted_job_ids == [] do
      {:ok, []}
    else
      workflow_id = changeset.data.id

      {_target_count, target_orphaned_ids} =
        from(e in Edge,
          where: e.workflow_id == ^workflow_id,
          where: e.target_job_id in ^deleted_job_ids,
          select: e.id
        )
        |> repo.update_all(set: [target_job_id: nil])

      {_source_count, source_orphaned_ids} =
        from(e in Edge,
          where: e.workflow_id == ^workflow_id,
          where: e.source_job_id in ^deleted_job_ids,
          select: e.id
        )
        |> repo.update_all(set: [source_job_id: nil])

      orphaned_edge_ids =
        Enum.uniq(target_orphaned_ids ++ source_orphaned_ids)

      Logger.debug(fn ->
        "Orphaned #{length(target_orphaned_ids)} target and #{length(source_orphaned_ids)} source edge refs for deleted jobs: #{inspect(deleted_job_ids)}"
      end)

      {:ok, orphaned_edge_ids}
    end
  end

  # Removes edges that were orphaned by job deletion and not retargeted.
  # Only deletes edges whose IDs were returned by orphan_jobs_being_deleted
  # AND that still have a NULL FK (target_job_id or source without trigger).
  defp cleanup_orphaned_edges(_repo, _workflow_id, []), do: {:ok, 0}

  defp cleanup_orphaned_edges(repo, workflow_id, orphaned_edge_ids) do
    {count, _} =
      from(e in Edge,
        where: e.workflow_id == ^workflow_id,
        where: e.id in ^orphaned_edge_ids,
        where:
          is_nil(e.target_job_id) or
            (is_nil(e.source_job_id) and is_nil(e.source_trigger_id))
      )
      |> repo.delete_all()

    Logger.debug(fn ->
      "Cleaned up #{count} orphaned edges for workflow #{workflow_id}"
    end)

    {:ok, count}
  end

  @doc """
  Creates a snapshot from a multi.

  When the multi already has a `:workflow` change, it is assumed to be changed
  or inserted and will attempt to build and insert a new snapshot.

  When there isn't a `:workflow` change, it tries to find a dependant model
  like a Job, Trigger or Edge and uses the workflow associated with that
  model.

  In this case we assume that the workflow wasn't actually updated,
  `Workflow.touch()` is called to bump the `updated_at` and the `lock_version`
  of the workflow before a snapshot is captured.
  """
  def capture_snapshot(%Multi{} = multi) do
    multi
    |> Multi.merge(fn changes ->
      if changes[:workflow] do
        # TODO: can we tell if `optimistic_lock` was used?
        # if we can, then we can use `touch` here as well, filling in a few
        # gaps where we want to capture a snapshot because the workflow
        # doesn't have one yet.
        Multi.new()
      else
        dependent_change = find_dependent_change(multi)

        Multi.new()
        |> Multi.run(:workflow, fn repo, _changes ->
          workflow =
            changes[dependent_change]
            |> Ecto.assoc(:workflow)
            |> repo.one!()
            |> Workflow.touch()
            |> repo.update!()

          {:ok, workflow}
        end)
      end
    end)
    |> insert_snapshot()
  end

  defp find_dependent_change(multi) do
    multi
    |> Multi.to_list()
    |> Enum.find_value(fn
      {key, {_action, %Ecto.Changeset{data: %mod{}}, _}}
      when mod in [Job, Edge, Trigger] ->
        key

      _other ->
        false
    end)
  end

  defp insert_snapshot(multi) do
    multi
    |> Multi.insert(
      :snapshot,
      &(Map.get(&1, :workflow) |> Snapshot.build()),
      returning: false
    )
    |> Multi.insert(:audit_snapshot_creation, fn changes ->
      %{snapshot: %{id: snapshot_id}, workflow: %{id: workflow_id}} = changes

      Audit.snapshot_created(workflow_id, snapshot_id, changes.actor)
    end)
  end

  defp maybe_audit_workflow_state_changes(multi, changeset) do
    changeset
    |> Ecto.Changeset.get_change(:triggers, [])
    |> Enum.reduce_while(nil, fn trigger_changeset, _previous ->
      case Ecto.Changeset.get_change(trigger_changeset, :enabled) do
        nil -> {:cont, nil}
        changed -> {:halt, {trigger_changeset.data.enabled, changed}}
      end
    end)
    |> case do
      nil ->
        multi

      {from, to} ->
        Ecto.Multi.insert(
          multi,
          :audit_workflow_state_change,
          fn %{workflow: %{id: workflow_id}, actor: actor} ->
            Audit.workflow_state_changed(
              if(to, do: "enabled", else: "disabled"),
              workflow_id,
              actor,
              %{before: %{enabled: from}, after: %{enabled: to}}
            )
          end
        )
    end
  end

  # Helper to preload associations only if they are present in the attributes
  defp maybe_preload(workflow, assoc, attrs) do
    List.wrap(assoc)
    |> Enum.filter(&Map.has_key?(attrs, &1))
    |> case do
      [] -> workflow
      assocs -> Repo.preload(workflow, assocs)
    end
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking workflow changes.

  ## Examples

      iex> change_workflow(workflow)
      %Ecto.Changeset{data: %Workflow{}}

  """
  def change_workflow(%Workflow{} = workflow, attrs \\ %{}) do
    workflow
    |> maybe_preload([:jobs, :triggers, :edges], attrs)
    |> Workflow.changeset(attrs)
  end

  @doc """
  Returns a list of workflows for a project with optional filtering, sorting, and preloading.

  ## Parameters
    * `project` - A %Project{} struct for which to retrieve workflows
    * `opts` - Optional keyword list of options

  ## Options
    * `:search` - String to filter workflows by name using case-insensitive partial matching
    * `:order_by` - A tuple containing the field and direction to sort by,
      e.g., `{:name, :asc}` or `{:enabled, :desc}`
    * `:include` - List of associations to preload (defaults to [:triggers, :edges, jobs: [:workflow]])

  ## Returns
    A list of %Workflow{} structs that match the criteria

  ## Examples

      # Get all workflows for a project
      iex> get_workflows_for(project)
      [%Workflow{}, ...]

      # Search workflows containing "api" in their name
      iex> get_workflows_for(project, search: "api")
      [%Workflow{name: "API Gateway"}, %Workflow{name: "External API"}]

      # Sort workflows by name in descending order
      iex> get_workflows_for(project, order_by: {:name, :desc})
      [%Workflow{name: "Zebra"}, %Workflow{name: "Apple"}]

      # Search and sort combined
      iex> get_workflows_for(project, search: "api", order_by: {:name, :desc})
      [%Workflow{name: "REST API"}, %Workflow{name: "API Gateway"}]

      # Customize preloaded associations
      iex> get_workflows_for(project, include: [:triggers])
      [%Workflow{triggers: [...]}, ...]
  """
  def get_workflows_for(%Project{} = project, opts \\ []) do
    include = Keyword.get(opts, :include, [:triggers, :edges, jobs: [:workflow]])
    order_by = Keyword.get(opts, :order_by, {:name, :asc})

    query =
      from(w in Workflow,
        where: is_nil(w.deleted_at) and w.project_id == ^project.id,
        preload: ^include
      )

    query =
      if search = Keyword.get(opts, :search) do
        from w in query, where: ilike(w.name, ^"%#{search}%")
      else
        query
      end

    query
    |> apply_sorting(order_by)
    |> Repo.all()
  end

  defp apply_sorting(query, {:name, direction}) when is_atom(direction) do
    from w in query, order_by: [{^direction, w.name}]
  end

  defp apply_sorting(query, {:enabled, direction}) when is_atom(direction) do
    from w in query,
      left_join: t in assoc(w, :triggers),
      group_by: w.id,
      order_by: [{^direction, fragment("COALESCE(MAX(?::int), 0)", t.enabled)}]
  end

  defp apply_sorting(query, _) do
    from w in query, order_by: [asc: w.name]
  end

  @doc """
  Returns a query for workflows accessible to a user
  """
  @spec workflows_for_user_query(Lightning.Accounts.User.t()) ::
          Ecto.Queryable.t()
  def workflows_for_user_query(%Lightning.Accounts.User{} = user) do
    Query.workflows_for(user)
  end

  @spec to_project_space([Workflow.t()]) :: %{}
  def to_project_space(workflows) when is_list(workflows) do
    %{
      "jobs" =>
        workflows
        |> Enum.flat_map(fn w -> w.jobs end)
        |> Enum.map(fn job ->
          %{
            "id" => job.id,
            "name" => job.name,
            "adaptor" => job.adaptor,
            "workflowId" => job.workflow_id
            # "trigger" => trigger_for_project_space(job)
          }
        end),
      "workflows" =>
        workflows
        |> Enum.map(fn w -> %{"id" => w.id, "name" => w.name} end)
    }
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for changing the workflow request_deletion.

  ## Examples

      iex> change_request_deletion(workflow)
      %Ecto.Changeset{data: %Workflow{}}

  """
  def mark_for_deletion(workflow, actor, _attrs \\ %{}) do
    workflow_triggers_query =
      from(t in Lightning.Workflows.Trigger,
        where: t.workflow_id == ^workflow.id
      )

    Multi.new()
    |> Multi.update(
      :workflow,
      soft_delete_changeset(Ecto.Changeset.change(workflow))
    )
    |> Multi.insert(:audit, Audit.marked_for_deletion(workflow.id, actor))
    |> Multi.update_all(
      :disable_triggers,
      workflow_triggers_query,
      # The path goes with the workflow's name, or a hidden row keeps it
      # reserved against a replacement.
      set: [enabled: false, custom_path: nil, legacy_bare_path: false]
    )
    |> Repo.transaction()
    |> tap(fn result ->
      with {:ok, _} <- result do
        preloaded = Repo.preload(workflow, [:triggers], force: true)
        Events.workflow_updated(preloaded)

        # The deletion goes out on the *project's* topic, not this module's:
        # sessions have to be told, and they cannot subscribe to a topic that
        # also fires on every save. See `Lightning.Projects.Events`.
        Lightning.Projects.Events.workflow_deleted(preloaded)
      end
    end)
  end

  @doc """
  Marks a workflow deleted and frees its name for reuse, in one step.

  The single soft-delete transition both `mark_for_deletion/3` and the
  provisioner route through, so a deleted workflow can never keep its name
  reserved on a hidden row.
  """
  @spec soft_delete_changeset(Ecto.Changeset.t(Workflow.t())) ::
          Ecto.Changeset.t(Workflow.t())
  def soft_delete_changeset(
        %Ecto.Changeset{data: %Workflow{} = workflow} = changeset
      ) do
    changeset
    |> Workflow.request_deletion_changeset(%{
      deleted_at: DateTime.utc_now() |> DateTime.truncate(:second)
    })
    |> Ecto.Changeset.put_change(
      :name,
      resolve_name_for_pending_deletion(workflow)
    )
  end

  @doc """
  Computes the `name_del`-style name a workflow should take when it is soft
  deleted, so it frees up its original name for reuse within the project.

  Used by `soft_delete_changeset/1`, which every delete path routes through.
  """
  @spec resolve_name_for_pending_deletion(Workflow.t()) :: String.t()
  def resolve_name_for_pending_deletion(%Workflow{
        name: name,
        project_id: project_id
      }) do
    base_name = "#{name}_del"

    existing_names =
      from(w in Workflow,
        where:
          w.project_id == ^project_id and
            (w.name == ^base_name or like(w.name, ^"#{base_name}%")),
        select: w.name
      )
      |> Repo.all()
      |> MapSet.new()

    find_available_name(base_name, existing_names)
  end

  defp find_available_name(base_name, existing_names, n \\ 0) do
    candidate = if n == 0, do: base_name, else: "#{base_name}#{n}"

    if MapSet.member?(existing_names, candidate),
      do: find_available_name(base_name, existing_names, n + 1),
      else: candidate
  end

  @doc """
  Permanently deletes workflows that were marked for deletion long enough ago
  and have no history left.

  A workflow becomes purgeable `purge_deleted_after_days` days after it was
  marked for deletion, and only once the last of its work orders is gone.
  Deleting a workflow's history is the data retention policy's job, not this
  one's: a workflow whose project keeps history forever is never purged, and
  one whose retention window is shorter than the purge window is purged on the
  first nightly sweep after its history expires.

  An unset `purge_deleted_after_days` reads as zero days, in line with the
  other purge workers — the cron entry driving this is only registered when
  the setting is greater than zero.
  """
  @impl Oban.Worker
  def perform(%Oban.Job{
        args: %{"workflow_id" => workflow_id, "type" => "purge_deleted"}
      }) do
    case Repo.get(Workflow, workflow_id) do
      nil ->
        :ok

      %Workflow{deleted_at: nil} ->
        # The workflow came back between this job being enqueued and it
        # running. A purge can't be undone, so leave it alone.
        :ok

      workflow ->
        case delete_workflow(workflow) do
          {:ok, _workflow} ->
            :ok

          {:error, :has_history} ->
            # History arrived, or outlasted its expected retention window,
            # between this job being enqueued and it running. Not an error:
            # tomorrow's sweep re-checks and enqueues the workflow again.
            {:cancel, :has_history}
        end
    end
  end

  def perform(%Oban.Job{args: %{"type" => "purge_deleted"}}) do
    jobs =
      purgeable_workflows_query()
      |> Repo.all()
      |> Enum.map(fn workflow_id ->
        new(%{workflow_id: workflow_id, type: "purge_deleted"}, max_attempts: 3)
      end)

    Oban.insert_all(Lightning.Oban, jobs)

    :ok
  end

  defp purgeable_workflows_query do
    days = Config.purge_deleted_after_days() || 0

    from(w in Workflow,
      as: :workflow,
      where: not is_nil(w.deleted_at) and w.deleted_at <= ago(^days, "day"),
      where: not exists(workflow_history_query()),
      select: w.id
    )
  end

  defp workflow_history_query do
    from(wo in WorkOrder,
      where: wo.workflow_id == parent_as(:workflow).id,
      select: 1
    )
  end

  @doc """
  Permanently deletes a workflow that has no history left.

  Returns `{:error, :has_history}` for a workflow that still has work orders.
  Their history belongs to the project and is the data retention policy's to
  remove; until it does, work orders and steps hold `RESTRICT` references to
  the workflow's snapshots and the delete could not succeed anyway.

  Deleting the workflow row cascades to its jobs, triggers, edges, snapshots,
  versions, templates and AI chat sessions. Project-scoped records the
  workflow merely referenced, dataclips above all, are left where they are:
  they belong to the project and outlive it.
  """
  @spec delete_workflow(Workflow.t()) ::
          {:ok, Workflow.t()} | {:error, :has_history | Ecto.Changeset.t()}
  def delete_workflow(%Workflow{} = workflow) do
    if has_history?(workflow) do
      {:error, :has_history}
    else
      Logger.debug(fn ->
        # coveralls-ignore-start
        "Deleting workflow ##{workflow.id}..."
        # coveralls-ignore-stop
      end)

      Repo.delete(workflow)
    end
  end

  @doc """
  Whether any work orders are still recorded against `workflow`.
  """
  @spec has_history?(Workflow.t()) :: boolean()
  def has_history?(%Workflow{id: workflow_id}) do
    Repo.exists?(from(wo in WorkOrder, where: wo.workflow_id == ^workflow_id))
  end

  @doc """
  Creates an edge
  """
  def create_edge(attrs, actor) do
    Multi.new()
    |> Multi.put(:actor, actor)
    |> Multi.insert(:edge, Edge.new(attrs))
    |> capture_snapshot()
    |> Repo.transaction()
    |> case do
      {:ok, %{edge: edge}} ->
        {:ok, edge}

      {:error, _run, changeset, _changes} ->
        {:error, changeset}
    end
  end

  @doc """
  Gets a single Webhook Trigger from the segments of an `/i/` request path.

  Tried in order, and no step can match more than one row, so a request can
  never fail on an ambiguous path:

    1. A project id and a custom path, when there is a second segment.
    2. The first segment as a trigger id.
    3. A bare custom path, for the triggers that held one before paths were
       namespaced. That set is fixed at migration time and never grows.

  Trailing segments are ignored: `/i/<trigger-uuid>/Patient` posts to the same
  trigger as `/i/<trigger-uuid>`.
  """
  @spec get_webhook_trigger([String.t()], keyword()) :: Trigger.t() | nil
  def get_webhook_trigger(segments, opts \\ [])

  # Ordered so the likely answer is the first query. A request carrying a second
  # segment is almost always the namespaced form, and one carrying none can only
  # be an id or a legacy bare path.
  def get_webhook_trigger([first | rest], opts) do
    case cast_uuid(first) do
      {:ok, id} when rest != [] ->
        by_project_path(id, rest, opts) || by_trigger_id(id, opts) ||
          by_legacy_path(first, opts)

      {:ok, id} ->
        by_trigger_id(id, opts) || by_legacy_path(first, opts)

      :error ->
        by_legacy_path(first, opts)
    end
  end

  def get_webhook_trigger(_segments, _opts), do: nil

  # `Ecto.UUID.cast/1` also accepts any 16-byte binary as a raw UUID, which
  # would swallow a 16-character custom path like `orders_intake_v1`. Only the
  # 36-character textual form is a URL segment we mean to read as an id.
  defp cast_uuid(<<_::288>> = segment), do: Ecto.UUID.cast(segment)
  defp cast_uuid(_segment), do: :error

  defp by_trigger_id(id, opts) do
    Trigger |> where([t], t.id == ^id) |> fetch_webhook(opts)
  end

  defp by_project_path(project_id, [custom_path | _rest], opts) do
    Trigger
    |> where([t], t.project_id == ^project_id and t.custom_path == ^custom_path)
    |> fetch_webhook(opts)
  end

  defp by_legacy_path(custom_path, opts) do
    Trigger
    |> where([t], t.legacy_bare_path and t.custom_path == ^custom_path)
    |> fetch_webhook(opts)
  end

  defp fetch_webhook(query, opts) do
    query
    |> where([t], t.type == :webhook)
    |> preload(^Keyword.get(opts, :include, []))
    |> Repo.one()
  end

  @doc """
  Gets an `Edge` by its associated `Trigger`.

  ## Parameters
  - `%Trigger{id: trigger_id}`: A `Trigger` struct from which the associated `Edge` is to be found.

  ## Returns
  - Returns an `Edge` struct preloaded with its `source_trigger` and `target_job` if found.
  - Returns `nil` if no `Edge` is associated with the given `Trigger`.

  ## Examples
  ```
  trigger = %Trigger{id: 1, ...}
  Lightning.Workflows.get_edge_by_trigger(trigger)
  # => %Edge{source_trigger: %Trigger{}, target_job: %Job{}, ...}

  non_existent_trigger = %Trigger{id: 999, ...}
  Lightning.Workflows.get_edge_by_trigger(non_existent_trigger)
  # => nil
  ```
  """
  def get_edge_by_trigger(%Trigger{id: trigger_id}) do
    from(e in Edge,
      join: j in Job,
      on: j.id == e.target_job_id,
      left_join: t in Trigger,
      on: e.source_trigger_id == t.id,
      where: t.id == ^trigger_id,
      preload: [:source_trigger, :target_job]
    )
    |> Repo.one()
  end

  @doc """
  Returns a list of edges with jobs to execute, given a current timestamp in Unix. This is
  used by the scheduler, which calls this function once every minute.
  """
  @spec get_edges_for_cron_execution(DateTime.t()) :: [Edge.t()]
  def get_edges_for_cron_execution(datetime) do
    cron_edges =
      Query.enabled_cron_jobs_by_edge()
      |> Repo.all()

    for e <- cron_edges,
        has_matching_trigger(e, datetime),
        do: e
  end

  defp has_matching_trigger(edge, datetime) do
    cron_expression = edge.source_trigger.cron_expression

    with {:ok, cron} <- Crontab.CronExpression.Parser.parse(cron_expression),
         true <- Crontab.DateChecker.matches_date?(cron, datetime) do
      edge
    else
      _other -> false
    end
  end

  @doc """
  Builds a Trigger
  """
  def build_trigger(attrs) do
    attrs
    |> Trigger.new()
    |> Repo.insert()
  end

  @doc """
  Updates a trigger
  """
  def update_trigger(trigger, attrs) do
    trigger
    |> Trigger.changeset(attrs)
    |> Repo.update()
  end

  @doc """
    Checks if a workflow exists in the given project
  """
  def workflow_exists_in_project?(project_id, workflow_id) do
    get_workflow_for_project(%Project{id: project_id}, workflow_id) != nil
  end

  @doc """
  Creates a latest snapshot for the given workflow if one does not already exist
  for the current lock_version. Returns {:ok, snapshot} if a snapshot exists or is created.

  > #### Note {: .info}
  >
  > In normal situations this function is not needed as the snapshot is created
  > when the workflow is saved.
  """
  @spec maybe_create_latest_snapshot(Workflow.t()) ::
          {:ok, Snapshot.t()} | {:error, Ecto.Changeset.t(Snapshot.t())}
  def maybe_create_latest_snapshot(
        %Workflow{
          id: workflow_id,
          lock_version: lock_version,
          updated_at: updated_at,
          deleted_at: nil
        } = workflow
      ) do
    case Repo.get_by(Snapshot,
           workflow_id: workflow_id,
           lock_version: lock_version
         ) do
      nil ->
        workflow
        |> Snapshot.build()
        |> Repo.insert()
        |> tap(fn result ->
          with {:ok, _snapshot} <- result do
            Logger.warning(
              "Created latest snapshot for #{workflow_id} (last_update: #{updated_at})"
            )
          end
        end)

      snapshot ->
        {:ok, snapshot}
    end
  end

  @doc """
  Updates the `enabled` state of triggers associated with a given workflow as a struct or as a changeset.

  ## **Parameters**
  - **`workflow_or_changeset`**:
  - An `%Ecto.Changeset{}` containing a `:triggers` association.
  - A `%Workflow{}` struct with a `triggers` field.
  - **`enabled?`**:
  - A boolean indicating whether to enable (`true`) or disable (`false`) the triggers.

  ## **Returns**
  - An updated `%Ecto.Changeset{}` with the `:triggers` association modified.
  - An updated `%Ecto.Changeset{}` derived from the given `%Workflow{}`.

  ## **Examples**

  ### **Using an `Ecto.Changeset`**
  ```elixir
  changeset = Ecto.Changeset.change(%Workflow{}, %{triggers: [%Trigger{enabled: false}]})
  updated_changeset = update_triggers_enabled_state(changeset, true)
  # The triggers in the changeset will now have `enabled: true`.
  ```

  ### **Using a `Workflow` struct**
  ```elixir
  workflow = %Workflow{triggers: [%Trigger{enabled: false}]}
  updated_changeset = update_triggers_enabled_state(workflow, true)
  # The returned changeset will have triggers with `enabled: true`.
  ```
  """
  def update_triggers_enabled_state(
        %Ecto.Changeset{data: %Workflow{}} = changeset,
        enabled?
      ) do
    updated_triggers =
      changeset
      |> Ecto.Changeset.get_field(:triggers, [])
      |> update_triggers(enabled?)

    changeset
    |> Ecto.Changeset.put_assoc(:triggers, updated_triggers)
  end

  def update_triggers_enabled_state(%Workflow{} = workflow, enabled?) do
    updated_triggers =
      workflow.triggers
      |> update_triggers(enabled?)

    workflow
    |> change_workflow()
    |> Ecto.Changeset.put_assoc(:triggers, updated_triggers)
  end

  defp update_triggers(triggers, enabled?) do
    Enum.map(triggers, &Ecto.Changeset.change(&1, %{enabled: enabled?}))
  end
end
