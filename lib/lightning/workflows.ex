defmodule Lightning.Workflows do
  @moduledoc """
  The Workflows context.
  """

  import Ecto.Query

  alias Ecto.Multi

  alias Lightning.KafkaTriggers
  alias Lightning.Projects.Project
  alias Lightning.Repo
  alias Lightning.Workflows.Audit
  alias Lightning.Workflows.Edge
  alias Lightning.Workflows.Events
  alias Lightning.Workflows.Job
  alias Lightning.Workflows.Query
  alias Lightning.Workflows.Snapshot
  alias Lightning.Workflows.Trigger
  alias Lightning.Workflows.Triggers
  alias Lightning.Workflows.Workflow

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

  @spec save_workflow(Ecto.Changeset.t(Workflow.t()) | map(), struct()) ::
          {:ok, Workflow.t()}
          | {:error, Ecto.Changeset.t(Workflow.t())}
          | {:error, :workflow_deleted}
  def save_workflow(%Ecto.Changeset{data: %Workflow{}} = changeset, actor) do
    Multi.new()
    |> Multi.put(:actor, actor)
    |> Multi.run(:validate, fn _repo, _changes ->
      if is_nil(changeset.data.deleted_at) do
        {:ok, true}
      else
        {:error, :workflow_deleted}
      end
    end)
    |> Multi.insert_or_update(:workflow, changeset)
    |> then(fn multi ->
      if changeset.changes == %{} do
        multi
      else
        multi |> capture_snapshot()
      end
    end)
    |> maybe_audit_workflow_state_changes(changeset)
    |> Repo.transaction()
    |> case do
      {:ok, %{workflow: workflow}} ->
        publish_kafka_trigger_events(changeset)

        Events.workflow_updated(workflow)

        {:ok, workflow}

      {:error, :workflow, changeset, _changes} ->
        {:error, changeset}

      {:error, :snapshot, snapshot_changeset, %{workflow: workflow}} ->
        Logger.warning(fn ->
          """
          Failed to save snapshot for workflow: #{workflow.id}
          #{inspect(snapshot_changeset.errors)}
          """
        end)

        {:error, false}

      {:error, _action, reason, _changes} ->
        {:error, reason}
    end
  end

  def save_workflow(%{} = attrs, actor) do
    Workflow.changeset(%Workflow{}, attrs)
    |> save_workflow(actor)
  end

  @spec publish_kafka_trigger_events(Ecto.Changeset.t(Workflow.t())) :: :ok
  def publish_kafka_trigger_events(changeset) do
    changeset
    |> KafkaTriggers.get_kafka_triggers_being_updated()
    |> Enum.each(fn trigger_id ->
      Triggers.Events.kafka_trigger_updated(trigger_id)
    end)
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
      Workflow.request_deletion_changeset(workflow, %{
        "deleted_at" => DateTime.utc_now()
      })
    )
    |> Multi.insert(:audit, Audit.marked_for_deletion(workflow.id, actor))
    |> Multi.update_all(
      :disable_triggers,
      workflow_triggers_query,
      set: [enabled: false]
    )
    |> Repo.transaction()
    |> tap(fn result ->
      with {:ok, _} <- result do
        workflow
        |> Repo.preload([:triggers], force: true)
        |> tap(&notify_of_affected_kafka_triggers/1)
        |> Events.workflow_updated()
      end
    end)
  end

  defp notify_of_affected_kafka_triggers(%{triggers: triggers}) do
    triggers
    |> Enum.filter(&(&1.type == :kafka))
    |> Enum.each(&Triggers.Events.kafka_trigger_updated(&1.id))
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
  Gets a single Webhook Trigger by its `custom_path` or `id`.
  """
  def get_webhook_trigger(path, opts \\ []) when is_binary(path) do
    preloads = opts |> Keyword.get(:include, [])

    from(t in Trigger,
      where:
        fragment(
          "coalesce(?, ?)",
          t.custom_path,
          type(t.id, :string)
        ) == ^path and t.type == :webhook,
      preload: ^preloads
    )
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
    Check if workflow exist
  """
  def workflow_exists?(project_id, workflow_name) do
    query =
      from w in Workflow,
        where: w.project_id == ^project_id and w.name == ^workflow_name

    Repo.exists?(query)
  end

  @doc """
  A way to ensure the consistency of nodes.
  This query orders jobs based on their `inserted_at` timestamps in ascending order
  """
  def jobs_ordered_subquery do
    from(j in Job, order_by: [asc: j.inserted_at])
  end

  def has_newer_version?(%Workflow{lock_version: version, id: id}) do
    from(w in Workflow, where: w.lock_version > ^version and w.id == ^id)
    |> Repo.exists?()
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
