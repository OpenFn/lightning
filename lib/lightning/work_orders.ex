defmodule Lightning.WorkOrders do
  @moduledoc """
  Context for creating WorkOrders.

  ## Workorders

  Workorders represent the entrypoint for a unit of work in Lightning.
  They allow you to track the status of a webhook or cron trigger.

  For example if a user makes a request to a webhook endpoint, a Work Order
  is created with it's associated Workflow and Dataclip.

  Every Work Order has at least one Attempt, which represents a single
  invocation of the Workflow. If the workflow fails, and the attempt is retried,
  a new Attempt is created on the Work Order.

  This allows you group all the attempts for a single webhook, and track
  the success or failure of a given dataclip.

  ## Creating Work Orders

  Work Orders can be created in three ways:

  1. Via a webhook trigger
  2. Via a cron trigger
  3. Manually by a user (via the UI or API)

  Retries do not create new Work Orders, but rather new Attempts on the existing
  Work Order.
  """

  alias Lightning.AttemptRun
  alias Ecto.Multi
  alias Lightning.Accounts.User
  alias Lightning.Attempt
  alias Lightning.Attempts
  alias Lightning.Graph
  alias Lightning.Invocation.Dataclip
  alias Lightning.Invocation.Run
  alias Lightning.Repo

  alias Lightning.WorkOrder
  alias Lightning.WorkOrders.Events
  alias Lightning.WorkOrders.Manual
  alias Lightning.WorkOrders.Query

  alias Lightning.Workflows.Job
  alias Lightning.Workflows.Trigger
  alias Lightning.Workflows.Workflow

  import Ecto.Changeset
  import Ecto.Query
  import Lightning.Validators

  @type work_order_option ::
          {:workflow, Workflow.t()}
          | {:dataclip, Dataclip.t()}
          | {:created_by, User.t()}

  @doc """
  Create a new Work Order.

  **For a webhook**
      create_for(trigger, workflow: workflow, dataclip: dataclip)

  **For a user**
      create_for(job, workflow: workflow, dataclip: dataclip, user: user)
  """
  @spec create_for(Trigger.t() | Job.t(), [work_order_option()]) ::
          {:ok, WorkOrder.t()} | {:error, Ecto.Changeset.t(WorkOrder.t())}
  def create_for(%Trigger{} = trigger, opts) do
    build_for(trigger, opts |> Map.new())
    |> Repo.insert()
    |> maybe_broadcast_workorder_creation()
  end

  def create_for(%Job{} = job, opts) do
    build_for(job, opts |> Map.new())
    |> Repo.insert()
    |> maybe_broadcast_workorder_creation()
  end

  def create_for(%Manual{} = manual) do
    Multi.new()
    |> get_or_insert_dataclip(manual)
    |> Multi.insert(:workorder, fn %{dataclip: dataclip} ->
      build_for(manual.job, %{
        workflow: manual.workflow,
        dataclip: dataclip,
        created_by: manual.created_by
      })
    end)
    |> Multi.run(:broadcast, fn _repo,
                                %{workorder: %{attempts: [attempt]} = workorder} ->
      Events.work_order_created(manual.project.id, workorder)
      Events.attempt_created(manual.project.id, attempt)
      {:ok, nil}
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{workorder: workorder}} ->
        {:ok, workorder}
    end
  end

  defp maybe_broadcast_workorder_creation(result) do
    case result do
      {:ok, workorder} ->
        workflow = workorder |> Repo.preload(:workflow) |> Map.get(:workflow)
        Events.work_order_created(workflow.project_id, workorder)
        {:ok, workorder}

      other ->
        other
    end
  end

  defp get_or_insert_dataclip(multi, manual) do
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

  @spec build_for(Trigger.t() | Job.t(), map()) ::
          Ecto.Changeset.t(WorkOrder.t())
  def build_for(%Trigger{} = trigger, attrs) do
    %WorkOrder{}
    |> change()
    |> put_assoc(:workflow, attrs[:workflow])
    |> put_assoc(:trigger, trigger)
    |> put_assoc(:dataclip, attrs[:dataclip])
    |> put_assoc(:attempts, [
      Attempt.for(trigger, %{dataclip: attrs[:dataclip]})
    ])
    |> validate_required_assoc(:workflow)
    |> validate_required_assoc(:trigger)
    |> validate_required_assoc(:dataclip)
    |> assoc_constraint(:trigger)
    |> assoc_constraint(:workflow)
  end

  def build_for(%Job{} = job, attrs) do
    %WorkOrder{}
    |> change()
    |> put_assoc(:workflow, attrs[:workflow])
    |> put_assoc(:dataclip, attrs[:dataclip])
    |> put_assoc(:attempts, [
      Attempt.for(job, %{
        dataclip: attrs[:dataclip],
        created_by: attrs[:created_by]
      })
    ])
    |> validate_required_assoc(:workflow)
    |> validate_required_assoc(:dataclip)
    |> assoc_constraint(:trigger)
    |> assoc_constraint(:workflow)
  end

  @doc """
  Retry an Attempt from a given run.

  This will create a new Attempt on the Work Order, and enqueue it for
  processing.

  When creating a new Attempt, a graph of the workflow is created, and
  using that graph the runs would not be replaced with the new runs are linked.

  For example, by retrying a run from the middle of the workflow, the new
  attempt will only contain the runs that are upstream of the run being
  retried.
  """
  @spec retry(
          Attempt.t() | Ecto.UUID.t(),
          Run.t() | Ecto.UUID.t(),
          [
            work_order_option(),
            ...
          ]
          | []
        ) ::
          {:ok, Attempt.t()} | {:error, Ecto.Changeset.t(Attempt.t())}
  def retry(attempt, run, opts \\ [])

  def retry(attempt_id, run_id, opts)
      when is_binary(attempt_id) and is_binary(run_id) do
    attrs = Map.new(opts)

    attempt =
      from(a in Attempt,
        where: a.id == ^attempt_id,
        join: r in assoc(a, :runs),
        where: r.id == ^run_id,
        preload: [:runs, work_order: [workflow: :edges]]
      )
      |> Repo.one()

    run =
      from(r in Ecto.assoc(attempt, :runs),
        where: r.id == ^run_id,
        preload: [:job]
      )
      |> Repo.one()

    runs =
      attempt.work_order.workflow.edges
      |> Enum.reduce(Graph.new(), fn edge, graph ->
        graph
        |> Graph.add_edge(
          edge.source_trigger_id || edge.source_job_id,
          edge.target_job_id
        )
      end)
      |> Graph.prune(run.job_id)
      |> Graph.nodes()
      |> then(fn nodes ->
        Enum.filter(attempt.runs, fn run ->
          run.job_id in nodes
        end)
      end)

    changeset =
      Attempt.new(%{priority: :immediate})
      |> put_assoc(:created_by, attrs[:created_by])
      |> put_assoc(:work_order, attempt.work_order)
      |> put_change(:dataclip_id, run.input_dataclip_id)
      |> put_assoc(:work_order, attempt.work_order)
      |> put_assoc(:starting_job, run.job)
      |> put_assoc(:runs, runs)
      |> validate_required(:dataclip_id)
      |> validate_required_assoc(:work_order)
      |> validate_required_assoc(:created_by)

    Repo.transact(fn ->
      with {:ok, attempt} <- Attempts.enqueue(changeset),
           {:ok, _workorder} <- update_state(attempt) do
        {:ok, attempt}
      end
    end)
  end

  def retry(%Attempt{id: attempt_id}, %Run{id: run_id}, opts) do
    retry(attempt_id, run_id, opts)
  end

  @spec retry_many(
          [WorkOrder.t(), ...],
          job_id :: Ecto.UUID.t(),
          [work_order_option(), ...] | []
        ) :: {:ok, count :: integer()}
  def retry_many([%WorkOrder{} | _rest] = workorders, job_id, opts) do
    orders_ids = Enum.map(workorders, & &1.id)

    last_attempts_query =
      from(att in Attempt,
        join: r in assoc(att, :runs),
        where: att.work_order_id in ^orders_ids,
        group_by: att.work_order_id,
        select: %{
          work_order_id: att.work_order_id,
          last_inserted_at: max(att.inserted_at)
        }
      )

    attempt_runs_query =
      from(ar in AttemptRun,
        join: att in assoc(ar, :attempt),
        join: wo in assoc(att, :work_order),
        join: last in subquery(last_attempts_query),
        on:
          last.work_order_id == att.work_order_id and
            att.inserted_at == last.last_inserted_at,
        join: r in assoc(ar, :run),
        on: r.job_id == ^job_id,
        order_by: [asc: wo.inserted_at]
      )

    attempt_runs_query
    |> Repo.all()
    |> retry_many(opts)
  end

  @spec retry_many(
          [WorkOrder.t(), ...] | [AttemptRun.t(), ...],
          [work_order_option(), ...] | []
        ) :: {:ok, count :: integer()}
  def retry_many([%WorkOrder{} | _rest] = workorders, opts) do
    orders_ids = Enum.map(workorders, & &1.id)

    attempt_run_numbers_query =
      from(ar in AttemptRun,
        join: att in assoc(ar, :attempt),
        join: r in assoc(ar, :run),
        where: att.work_order_id in ^orders_ids,
        select: %{
          id: ar.id,
          row_num:
            row_number()
            |> over(
              partition_by: att.work_order_id,
              order_by: coalesce(r.started_at, r.inserted_at)
            )
        }
      )

    first_attempt_runs_query =
      from(ar in AttemptRun,
        join: arn in subquery(attempt_run_numbers_query),
        on: ar.id == arn.id,
        join: att in assoc(ar, :attempt),
        join: wo in assoc(att, :work_order),
        where: arn.row_num == 1,
        order_by: [asc: wo.inserted_at]
      )

    first_attempt_runs_query
    |> Repo.all()
    |> retry_many(opts)
  end

  def retry_many([%AttemptRun{} | _rest] = attempt_runs, opts) do
    for attempt_run <- attempt_runs do
      {:ok, _} = retry(attempt_run.attempt_id, attempt_run.run_id, opts)
    end

    {:ok, length(attempt_runs)}
  end

  @doc """
  Updates the state of a WorkOrder based on the state of an attempt.

  This considers the state of all attempts on the WorkOrder, with the
  Attempt passed in as the latest attempt.

  See `Lightning.WorkOrders.Query.state_for/1` for more details.
  """
  @spec update_state(Attempt.t()) ::
          {:ok, WorkOrder.t()}
  def update_state(%Attempt{} = attempt) do
    state_query = Query.state_for(attempt)

    from(wo in WorkOrder,
      where: wo.id == ^attempt.work_order_id,
      join: s in subquery(state_query),
      on: true,
      select: wo,
      update: [set: [state: s.state, last_activity: ^DateTime.utc_now()]]
    )
    |> Repo.update_all([], returning: true)
    |> then(fn {_, [wo]} ->
      updated_wo = Repo.preload(wo, :workflow)
      Events.work_order_updated(updated_wo.workflow.project_id, updated_wo)
      {:ok, wo}
    end)
  end

  @doc """
  Get a Work Order by id.

  Optionally preload associations by passing a list of atoms to `:include`.

      Lightning.WorkOrders.get(id, include: [:attempts])
  """
  @spec get(Ecto.UUID.t(), [{:include, [atom()]}]) :: WorkOrder.t() | nil
  def get(id, opts \\ []) do
    preloads = opts |> Keyword.get(:include, [])

    from(w in WorkOrder,
      where: w.id == ^id,
      preload: ^preloads
    )
    |> Repo.one()
  end

  defdelegate subscribe(project_id), to: Events
end
