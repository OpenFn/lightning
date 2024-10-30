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
  Gets a single workflow.

  Raises `Ecto.NoResultsError` if the Workflow does not exist.

  ## Examples

      iex> get_workflow!(123)
      %Workflow{}

      iex> get_workflow!(456)
      ** (Ecto.NoResultsError)

  """
  def get_workflow!(id), do: Repo.get!(Workflow, id)

  def get_workflow(id), do: Repo.get(Workflow, id)

  # TODO Change typespec from any() to struct() when done
  @spec save_workflow(Ecto.Changeset.t(Workflow.t()) | map(), any()) ::
          {:ok, Workflow.t()} | {:error, Ecto.Changeset.t(Workflow.t())}
  def save_workflow(%Ecto.Changeset{data: %Workflow{}} = changeset, actor) do
    Multi.new()
    |> Multi.put(:actor, actor)
    |> Multi.insert_or_update(:workflow, changeset)
    |> then(fn multi ->
      if changeset.changes == %{} do
        multi
      else
        multi |> capture_snapshot()
      end
    end)
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
      {key, {_action, changeset_or_struct, _}} ->
        case changeset_or_struct do
          %{data: %{__struct__: model}} when model in [Job, Edge, Trigger] ->
            key

          _other ->
            false
        end

      {_key, {:put, _struct}} ->
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
    |> Multi.insert(:audit, fn changes ->
      %{snapshot: %{id: snapshot_id}, workflow: %{id: workflow_id}} = changes

      Audit.snapshot_created(workflow_id, snapshot_id, changes.actor)
    end)
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
  Retrieves a list of active Workflows with their jobs and triggers preloaded.
  """
  @spec get_workflows_for(Project.t()) :: [Workflow.t()]
  def get_workflows_for(%Project{} = project) do
    from(w in Workflow,
      preload: [:triggers, :edges, jobs: [:workflow]],
      where: is_nil(w.deleted_at) and w.project_id == ^project.id,
      order_by: [asc: w.name]
    )
    |> Repo.all()
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
  def mark_for_deletion(workflow, _attrs \\ %{}) do
    workflow_triggers_query =
      from(t in Lightning.Workflows.Trigger,
        where: t.workflow_id == ^workflow.id
      )

    Repo.transaction(fn ->
      Workflow.request_deletion_changeset(workflow, %{
        "deleted_at" => DateTime.utc_now()
      })
      |> Repo.update()

      Repo.update_all(workflow_triggers_query, set: [enabled: false])
    end)
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
  Gets a Single Edge by it's webhook trigger.
  """
  def get_webhook_trigger(path, opts \\ []) when is_binary(path) do
    preloads = opts |> Keyword.get(:include, [])

    from(t in Trigger,
      where:
        fragment(
          "coalesce(?, ?)",
          t.custom_path,
          type(t.id, :string)
        ) == ^path,
      preload: ^preloads
    )
    |> Repo.one()
  end

  @doc """
  Gets a single `Trigger` by its `custom_path` or `id`.

  ## Parameters
  - `path`: A binary string representing the `custom_path` or `id` of the trigger.

  ## Returns
  - Returns a `Trigger` struct if a trigger is found.
  - Returns `nil` if no trigger is found for the given `path`.

  ## Examples

  ```
  Lightning.Workflows.get_trigger_by_webhook("some_path_or_id")
  # => %Trigger{id: 1, custom_path: "some_path_or_id", ...}

  Lightning.Workflows.get_trigger_by_webhook("non_existent_path_or_id")
  # => nil
  ```
  """
  def get_trigger_by_webhook(path) when is_binary(path) do
    from(t in Trigger,
      where:
        fragment("coalesce(?, ?)", t.custom_path, type(t.id, :string)) == ^path
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
end
