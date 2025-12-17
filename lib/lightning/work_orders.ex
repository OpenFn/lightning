defmodule Lightning.WorkOrders do
  @moduledoc """
  Context for creating WorkOrders.

  ## Work Orders

  Work Orders represent the entrypoint for a unit of work in Lightning.
  They allow you to track the status of a webhook or cron trigger.

  For example if a user makes a request to a webhook endpoint, a Work Order
  is created with it's associated Workflow and Dataclip.

  Every Work Order has at least one Run, which represents a single
  invocation of the Workflow. If the workflow fails, and the run is retried,
  a new Run is created on the Work Order.

  This allows you group all the runs for a single webhook, and track
  the success or failure of a given dataclip.

  ## Creating Work Orders

  Work Orders can be created in three ways:

  1. Via a webhook trigger
  2. Via a cron trigger
  3. Manually by a user (via the UI or API)

  Retries do not create new Work Orders, but rather new Runs on the existing
  Work Order.
  """
  import Ecto.Changeset
  import Ecto.Query
  import Lightning.Validators
  import Lightning.ChangesetUtils

  alias Ecto.Multi
  alias Lightning.Accounts.User
  alias Lightning.Extensions.UsageLimiting
  alias Lightning.Extensions.UsageLimiting.Action
  alias Lightning.Extensions.UsageLimiting.Context
  alias Lightning.Graph
  alias Lightning.Invocation.Dataclip
  alias Lightning.Invocation.Step
  alias Lightning.Repo
  alias Lightning.Run
  alias Lightning.Runs
  alias Lightning.RunStep
  alias Lightning.Services.UsageLimiter
  alias Lightning.Workflows.Edge
  alias Lightning.Workflows.Job
  alias Lightning.Workflows.Snapshot
  alias Lightning.Workflows.Trigger
  alias Lightning.Workflows.Workflow
  alias Lightning.WorkOrder
  alias Lightning.WorkOrders.Events
  alias Lightning.WorkOrders.Manual
  alias Lightning.WorkOrders.Query
  alias Lightning.WorkOrders.RetryManyWorkOrdersJob

  @type dataclip_input ::
          Dataclip.t()
          | Ecto.Changeset.t(Dataclip.t())
          | map()

  @type work_order_option ::
          {:workflow, Workflow.t()}
          | {:dataclip, dataclip_input()}
          | {:created_by, User.t()}
          | {:project_id, Ecto.UUID.t()}
          | {:without_run, boolean()}

  @retry_many_chunk_size 100

  defdelegate subscribe, to: Events
  defdelegate subscribe(project_id), to: Events

  @spec limit_run_creation(Ecto.UUID.t(), non_neg_integer()) ::
          :ok | UsageLimiting.error()
  def limit_run_creation(project_id, runs_count \\ 1) do
    UsageLimiter.limit_action(
      %Action{type: :new_run, amount: runs_count},
      %Context{
        project_id: project_id
      }
    )
  end

  @doc """
  Create a new Work Order.

  **For a webhook**
      create_for(trigger, workflow: workflow, dataclip: dataclip)
  """
  @spec create_for(Trigger.t(), Multi.t(), [work_order_option()]) ::
          {:ok, WorkOrder.t()}
          | {:error, Ecto.Changeset.t(WorkOrder.t()) | :workflow_deleted}
  def create_for(%Trigger{} = trigger, multi \\ Multi.new(), opts) do
    multi
    |> Multi.put(:workflow, opts[:workflow])
    |> get_or_insert_dataclip(opts[:dataclip])
    |> Multi.insert(:workorder, fn %{dataclip: dataclip} ->
      {without_run?, opts} = Keyword.pop(opts, :without_run, false)

      attrs =
        opts
        |> Map.new()
        |> Map.merge(%{dataclip: dataclip})
        |> then(fn attrs ->
          if without_run? do
            attrs |> Map.put(:state, :rejected)
          else
            attrs
          end
        end)

      build_for(trigger, attrs)
    end)
    |> Runs.enqueue()
    |> emit_and_return_work_order()
  end

  def create_for(%Manual{} = manual) do
    Multi.new()
    |> Multi.run(:workflow_deleted?, fn _repo, _changes ->
      if manual.workflow.deleted_at do
        {:error, :workflow_deleted}
      else
        {:ok, false}
      end
    end)
    |> get_or_insert_dataclip(manual)
    |> Multi.put(:workflow, manual.workflow)
    |> Multi.insert(:workorder, fn %{dataclip: dataclip} ->
      build_for(manual.job, %{
        workflow: manual.workflow,
        dataclip: dataclip,
        created_by: manual.created_by,
        priority: :immediate
      })
    end)
    |> Runs.enqueue()
    |> emit_and_return_work_order()
  end

  defp emit_and_return_work_order(
         {:ok, %{workorder: workorder, workflow: workflow}}
       ) do
    Enum.each(workorder.runs, &Events.run_created(workflow.project_id, &1))
    Events.work_order_created(workflow.project_id, workorder)
    {:ok, workorder}
  end

  defp emit_and_return_work_order({:error, _op, changeset, _changes}) do
    {:error, changeset}
  end

  defp maybe_get_snapshot(multi, workflow \\ nil, name \\ :snapshot) do
    multi
    |> Multi.merge(fn
      %{^name => _snapshot} ->
        # already present when enqueuing multiple runs with the same snapshot
        Multi.new()

      changes ->
        workflow = workflow || changes[:workflow]
        Snapshot.include_latest_snapshot(Multi.new(), name, workflow)
    end)
  end

  defp get_or_insert_dataclip(multi, %Manual{} = manual) do
    if manual.dataclip_id do
      multi |> Multi.one(:dataclip, where(Dataclip, id: ^manual.dataclip_id))
    else
      multi
      |> Multi.insert(
        :dataclip,
        Dataclip.new(
          body: manual.body |> Jason.decode!(),
          project_id: manual.project.id,
          type: :saved_input
        )
      )
    end
  end

  defp get_or_insert_dataclip(
         multi,
         %Ecto.Changeset{data: %Dataclip{}} = dataclip
       ) do
    multi |> Multi.insert(:dataclip, dataclip)
  end

  defp get_or_insert_dataclip(multi, %Dataclip{} = dataclip) do
    multi |> Multi.one(:dataclip, where(Dataclip, id: ^dataclip.id))
  end

  defp get_or_insert_dataclip(multi, params) when is_map(params) do
    get_or_insert_dataclip(multi, Dataclip.new(params))
  end

  defp build(attrs) do
    %WorkOrder{}
    |> change()
    |> put_if_provided(:state, attrs)
    |> put_assoc(:snapshot, Snapshot.get_current_for(attrs[:workflow]))
    |> put_assoc(:workflow, attrs[:workflow])
    |> put_assoc(:dataclip, attrs[:dataclip])
  end

  @spec build_for(Trigger.t() | Job.t(), map()) ::
          Ecto.Changeset.t(WorkOrder.t())
  def build_for(%Trigger{} = trigger, attrs) do
    build(attrs)
    |> put_assoc(:trigger, trigger)
    |> then(fn changeset ->
      changeset
      |> fetch_change(:state)
      |> case do
        {:ok, :rejected} ->
          changeset |> put_assoc(:runs, [])

        _any ->
          snapshot = changeset |> get_change(:snapshot)
          run_options = get_run_options(snapshot, attrs[:dataclip])

          changeset
          |> put_assoc(:runs, [
            Run.for(trigger, %{
              dataclip: attrs[:dataclip],
              snapshot: snapshot,
              options: run_options
            })
          ])
      end
    end)
    |> validate_required_assoc(:snapshot)
    |> validate_required_assoc(:workflow)
    |> validate_required_assoc(:trigger)
    |> validate_required_assoc(:dataclip)
    |> assoc_constraint(:trigger)
    |> assoc_constraint(:workflow)
    |> assoc_constraint(:snapshot)
  end

  def build_for(%Job{} = job, attrs) do
    build(attrs)
    |> then(fn changeset ->
      snapshot = changeset |> get_change(:snapshot)
      run_options = get_run_options(snapshot, attrs[:dataclip])

      runs =
        attrs[:runs] ||
          Run.for(job, %{
            dataclip: attrs[:dataclip],
            created_by: attrs[:created_by],
            priority: attrs[:priority],
            snapshot: snapshot,
            options: run_options
          })
          |> List.wrap()

      put_assoc(changeset, :runs, runs)
    end)
    |> validate_required_assoc(:snapshot)
    |> validate_required_assoc(:workflow)
    |> validate_required_assoc(:dataclip)
    |> assoc_constraint(:workflow)
    |> assoc_constraint(:snapshot)
  end

  defp get_run_options(%{} = snapshot, %{} = dataclip) do
    workflow_id = snapshot |> change() |> get_field(:workflow_id)
    project_id = dataclip |> change() |> get_field(:project_id)
    Runs.get_run_options(workflow_id, project_id)
  end

  defp get_run_options(_, _), do: nil

  @doc """
  Retry a run from a given step.

  This will create a new Run on the Work Order, and enqueue it for
  processing.

  When creating a new Run, a graph of the workflow is created steps that are
  independent from the selected step and its downstream flow are associated with
  this new run, but not executed again.
  """
  @spec retry(
          Run.t() | Ecto.UUID.t(),
          Step.t() | Ecto.UUID.t(),
          [work_order_option(), ...]
        ) ::
          {:ok, Run.t()} | {:error, Ecto.Changeset.t() | :workflow_deleted}
  def retry(%Run{id: run_id}, %Step{id: step_id}, opts) do
    retry(run_id, step_id, opts)
  end

  def retry(run_id, step_id, opts)
      when is_binary(run_id) and is_binary(step_id) do
    Multi.new()
    |> Multi.one(
      :run,
      from(a in Run,
        where: a.id == ^run_id,
        join: s in assoc(a, :steps),
        where: s.id == ^step_id,
        preload: [
          steps: [snapshot: [triggers: :webhook_auth_methods]],
          work_order: [workflow: :edges]
        ]
      )
    )
    |> Multi.one(:step, fn %{run: run} ->
      from(s in Ecto.assoc(run, :steps),
        join: d in assoc(s, :input_dataclip),
        where: s.id == ^step_id and is_nil(d.wiped_at),
        preload: [:job]
      )
    end)
    |> Multi.run(:workflow_deleted?, fn _repo, %{run: run} ->
      if run.work_order.workflow.deleted_at do
        {:error, :workflow_deleted}
      else
        {:ok, false}
      end
    end)
    |> Multi.run(:input_dataclip_id, fn
      _repo, %{step: %Step{input_dataclip_id: input_dataclip_id}} ->
        {:ok, input_dataclip_id}

      _repo, _wiped ->
        {:error,
         %Run{}
         |> Ecto.Changeset.change()
         |> Ecto.Changeset.add_error(
           :input_dataclip_id,
           "cannot retry run using a wiped dataclip"
         )}
    end)
    |> Multi.run(:steps, &get_workflow_steps_from/2)
    |> enqueue_retry(Keyword.fetch!(opts, :created_by))
  end

  defp enqueue_retry(multi, creating_user) do
    multi
    |> Multi.run(:workflow, fn _repo, %{run: run} ->
      {:ok, run.work_order.workflow}
    end)
    |> maybe_get_snapshot()
    |> Multi.insert(:new_run, fn %{
                                   run: run,
                                   step: step,
                                   steps: steps,
                                   snapshot: snapshot,
                                   input_dataclip_id: dataclip_id
                                 } ->
      new_retry_run(
        snapshot,
        run.work_order,
        dataclip_id,
        step.job,
        steps,
        creating_user
      )
    end)
    |> Multi.update_all(
      :workorder,
      fn %{new_run: run} ->
        update_workorder_query(run)
      end,
      [],
      returning: true
    )
    |> Runs.enqueue()
    |> case do
      {:ok, %{new_run: run, workorder: {1, [workorder]}, workflow: workflow}} ->
        Events.work_order_updated(workflow.project_id, workorder)
        Events.run_created(workflow.project_id, run)
        {:ok, run}

      {:error, _name, changeset, _changes} ->
        {:error, changeset}
    end
  end

  defp get_workflow_steps_from(_repo, %{
         run: %Run{
           steps: run_steps,
           work_order: %{workflow: %Workflow{edges: edges}}
         },
         step: %Step{
           job_id: step_job_id
         }
       }) do
    edges
    |> Enum.reduce(Graph.new(), fn item, graph ->
      Graph.add_edge(graph, item)
    end)
    |> Graph.prune(step_job_id)
    |> Graph.nodes()
    |> then(fn nodes ->
      Enum.filter(run_steps, fn step ->
        step.job_id in nodes
      end)
    end)
    |> then(&{:ok, &1})
  end

  defp get_workflow_steps_from(_repo, _changes), do: {:ok, []}

  @spec retry_many(
          [WorkOrder.t(), ...],
          job_id :: Ecto.UUID.t(),
          [work_order_option(), ...]
        ) ::
          {:ok, enqueued_count :: non_neg_integer(),
           discarded_count :: non_neg_integer()}
          | UsageLimiting.error()
          | {:error, :enqueue_error}
  def retry_many([%WorkOrder{} | _rest] = workorders, job_id, opts) do
    workorders
    |> Enum.map(& &1.id)
    |> last_run_steps_query([job_id])
    |> Repo.all()
    |> retry_many(opts)
  end

  @spec retry_many(
          [WorkOrder.t(), ...] | [RunStep.t(), ...],
          [work_order_option(), ...]
        ) ::
          {:ok, enqueued_count :: non_neg_integer(),
           discarded_count :: non_neg_integer()}
          | UsageLimiting.error()
          | {:error, :enqueue_error}
  def retry_many([%WorkOrder{} | _rest] = workorders, opts) do
    retriable_workorders =
      workorders |> Enum.map(& &1.id) |> fetch_retriable_workorders()

    with project_id <- Keyword.fetch!(opts, :project_id),
         :ok <- limit_run_creation(project_id, length(retriable_workorders)) do
      creating_user = Keyword.fetch!(opts, :created_by)

      retriable_workorders
      |> Enum.chunk_every(@retry_many_chunk_size)
      |> Enum.map(fn chunk ->
        workorder_ids = Enum.map(chunk, & &1.id)

        RetryManyWorkOrdersJob.new(%{
          workorders_ids: workorder_ids,
          created_by: creating_user.id
        })
      end)
      |> then(fn jobs ->
        Oban.insert_all(Lightning.Oban, jobs)
      end)
      |> case do
        inserted_list when is_list(inserted_list) ->
          enqueued_count = length(retriable_workorders)
          discarded_count = length(workorders) - enqueued_count

          {:ok, enqueued_count, discarded_count}

        _error ->
          {:error, :enqueue_error}
      end
    end
  end

  def retry_many([%RunStep{} | _rest] = run_steps, opts) do
    with project_id <- Keyword.fetch!(opts, :project_id),
         runs <- Enum.uniq_by(run_steps, & &1.run_id),
         :ok <- limit_run_creation(project_id, length(runs)) do
      results =
        Enum.map(run_steps, fn run_step ->
          retry(run_step.run_id, run_step.step_id, opts)
        end)

      success_count =
        Enum.count(results, fn result -> match?({:ok, _}, result) end)

      {:ok, success_count, Enum.count(results) - success_count}
    end
  end

  def retry_many([], _opts) do
    {:ok, 0, 0}
  end

  def get_workorders_with_runs(workflow_id, run_id) do
    # First, get workorder IDs we want
    workorder_ids =
      if is_nil(run_id) do
        # Just get top 20 workorders by last_activity
        from(wo in WorkOrder,
          join: r in assoc(wo, :runs),
          where: wo.workflow_id == ^workflow_id,
          group_by: wo.id,
          order_by: [desc: wo.last_activity],
          limit: 20,
          select: wo.id
        )
        |> Repo.all()
      else
        # Get the specific workorder for the run
        specific_wo_id =
          from(r in Run,
            where: r.id == ^run_id,
            select: r.work_order_id
          )
          |> Repo.one()

        # Get top 20 workorders
        other_wo_ids =
          from(wo in WorkOrder,
            join: r in assoc(wo, :runs),
            where: wo.workflow_id == ^workflow_id and wo.id != ^specific_wo_id,
            group_by: wo.id,
            order_by: [desc: wo.last_activity],
            # 19 because we're adding the specific one
            limit: 19,
            select: wo.id
          )
          |> Repo.all()

        # Combine them
        [specific_wo_id | other_wo_ids] |> Enum.uniq()
      end

    # Now fetch the full workorders with preloads
    from(wo in WorkOrder,
      where: wo.id in ^workorder_ids,
      order_by: [desc: wo.last_activity],
      preload: [:snapshot, runs: :snapshot]
    )
    |> Repo.all()
  end

  def get_last_runs_steps_with_dataclips(workorders, jobs) do
    job_ids = Enum.map(jobs, & &1.id)

    workorders
    |> Enum.map(& &1.id)
    |> last_run_steps_query(job_ids, non_wiped_dataclip?: true)
    |> Repo.all()
  end

  defp last_run_steps_query(workorder_ids, job_ids, opts \\ []) do
    last_runs_query =
      from(r in Run,
        where: r.work_order_id in ^workorder_ids,
        group_by: [r.work_order_id],
        select: %{
          work_order_id: r.work_order_id,
          last_inserted_at: max(r.inserted_at)
        }
      )

    from(rs in RunStep,
      join: r in assoc(rs, :run),
      join: s in assoc(rs, :step),
      join: wo in assoc(r, :work_order),
      join: lr in subquery(last_runs_query),
      on:
        r.work_order_id == lr.work_order_id and
          r.inserted_at == lr.last_inserted_at,
      where: s.job_id in ^job_ids,
      order_by: [asc: wo.inserted_at],
      select: %{rs | step: s, run: r}
    )
    |> then(fn query ->
      if Keyword.get(opts, :non_wiped_dataclip?) do
        query
        |> join(:inner, [rs, _r, s, _wo, _lr], d in assoc(s, :input_dataclip))
        |> where([_rs, _r, _s, _wo, _lr, d], is_nil(d.wiped_at))
      else
        query
      end
    end)
  end

  @doc """
  Enqueue multiple runs for retry in the same transaction.
  """
  def enqueue_many_for_retry(workorders_ids, creating_user_id) do
    workorders = workorders_with_first_runs(workorders_ids)
    creating_user = Repo.get!(User, creating_user_id)

    workorders
    |> Enum.with_index()
    |> Enum.reduce(Multi.new(), fn {workorder, index}, multi ->
      %{workflow: workflow, dataclip_id: dataclip_id} = workorder

      run_op = "run-#{index}"
      snapshot_op = "snapshot-#{workflow.id}"

      multi
      |> maybe_get_snapshot(workflow, snapshot_op)
      |> Multi.insert(run_op, fn %{^snapshot_op => snapshot} ->
        starting_job = determine_starting_job(workorder)

        new_retry_run(
          snapshot,
          workorder,
          dataclip_id,
          starting_job,
          [],
          creating_user
        )
      end)
      |> Multi.update_all(
        "workorder-#{index}",
        fn %{^run_op => run} ->
          update_workorder_query(run)
        end,
        [],
        returning: true
      )
    end)
    |> Multi.put(
      :workflow_runs_count,
      Enum.frequencies_by(workorders, & &1.workflow_id)
    )
    |> Runs.enqueue_many()
    |> case do
      {:ok, changes} ->
        {:ok, publish_events_for_retry_many(changes)}

      {:error, _name, changeset, _changes} ->
        {:error, changeset}
    end
  end

  @doc """
  Updates the state of a WorkOrder based on the state of a run.

  This considers the state of all runs on the WorkOrder, with the
  Run passed in as the latest run.

  See `Lightning.WorkOrders.Query.state_for/1` for more details.
  """
  @spec update_state(Run.t()) :: {:ok, WorkOrder.t()}
  def update_state(%Run{} = run) do
    run
    |> update_workorder_query()
    |> Repo.update_all([], returning: true)
    |> then(fn {_, [wo]} ->
      updated_wo = Repo.preload(wo, :workflow)
      Events.work_order_updated(updated_wo.workflow.project_id, updated_wo)
      {:ok, wo}
    end)
  end

  @doc """
  Get a Work Order by id.

  Optionally preload associations by passing a list to `:include`.
  Supports nested preloads.

      Lightning.WorkOrders.get(id, include: [:runs])
      Lightning.WorkOrders.get(id, include: [workflow: :project, runs: []])
  """
  @spec get(Ecto.UUID.t(), [{:include, list()}]) :: WorkOrder.t() | nil
  def get(id, opts \\ []) do
    preloads = opts |> Keyword.get(:include, [])

    from(w in WorkOrder,
      where: w.id == ^id,
      preload: ^preloads
    )
    |> Repo.one()
  end

  @doc """
  Returns a query for work orders belonging to a specific project
  """
  @spec work_orders_for_project_query(Lightning.Projects.Project.t()) ::
          Ecto.Queryable.t()
  def work_orders_for_project_query(%Lightning.Projects.Project{} = project) do
    Lightning.Invocation.Query.work_orders_for(project)
  end

  defp new_retry_run(
         snapshot,
         workorder,
         dataclip_id,
         starting_job,
         steps,
         creating_user
       ) do
    run_options =
      Runs.get_run_options(workorder.workflow.id, workorder.workflow.project_id)

    Run.new(%{priority: :immediate, dataclip_id: dataclip_id})
    |> put_assoc(:snapshot, snapshot)
    |> put_assoc(:work_order, workorder)
    |> put_assoc(:starting_job, starting_job)
    |> put_assoc(:steps, steps)
    |> put_assoc(:created_by, creating_user)
    |> put_embed(:options, run_options)
    |> validate_required_assoc(:snapshot)
    |> validate_required_assoc(:work_order)
    |> validate_required_assoc(:created_by)
    |> validate_required(:dataclip_id)
  end

  defp update_workorder_query(run) do
    state_query = Query.state_for(run)

    from(wo in WorkOrder,
      where: wo.id == ^run.work_order_id,
      join: s in subquery(state_query),
      on: true,
      select: wo,
      update: [set: [state: s.state, last_activity: ^DateTime.utc_now()]]
    )
  end

  defp publish_events_for_retry_many(changes) do
    runs = get_from_changes("run", changes)

    "workorder"
    |> get_from_changes(changes)
    |> Enum.each(fn {1, [workorder]} ->
      project_id =
        Enum.find_value(runs, fn run ->
          if run.work_order_id == workorder.id,
            do: run.work_order.workflow.project_id
        end)

      Events.work_order_updated(project_id, workorder)
    end)

    Enum.each(runs, &Events.run_created(&1.work_order.workflow.project_id, &1))

    runs
  end

  defp get_from_changes(key_prefix, changes) do
    changes
    |> Enum.reduce([], fn {k, v}, acc ->
      if String.starts_with?(to_string(k), key_prefix),
        do: [v | acc],
        else: acc
    end)
  end

  defp determine_starting_job(%{runs: [], workflow: %{edges: [edge]}}) do
    edge.target_job
  end

  defp determine_starting_job(%{runs: [run]}) do
    run.starting_job || hd(run.starting_trigger.edges).target_job
  end

  defp fetch_retriable_workorders(workorder_ids) do
    workorder_ids
    |> workorders_with_dataclips_query()
    |> join(:inner, [wo], wf in assoc(wo, :workflow), as: :workflow)
    |> where([workflow: wf], is_nil(wf.deleted_at))
    |> Repo.all()
  end

  defp workorders_with_dataclips_query(workorder_ids) do
    from(w in WorkOrder,
      join: d in assoc(w, :dataclip),
      where: w.id in ^workorder_ids and is_nil(d.wiped_at),
      order_by: [asc: w.inserted_at]
    )
  end

  defp workorders_with_first_runs(workorder_ids) do
    workorder_ids
    |> workorders_with_dataclips_query()
    |> preload(
      workflow: [edges: ^first_edge_query()],
      runs: ^first_run_query()
    )
    |> Repo.all()
  end

  defp first_run_query do
    from r in Run,
      order_by: [asc: coalesce(r.started_at, r.inserted_at)],
      preload: [:starting_job, starting_trigger: [edges: :target_job]],
      limit: 1
  end

  defp first_edge_query do
    from e in Edge,
      where: not is_nil(e.source_trigger_id),
      preload: :target_job
  end
end
