defmodule Lightning.WorkOrders do
  @moduledoc """
  Context for creating Workorders.

  ## Workorders

  Workorders represent the entrypoint for a unit of work in Lightning.
  They allow you to track the status of a webhook or cron trigger.

  For example if a user makes a request to a webhook endpoint, a Workorder
  is created with it's associated Workflow and Dataclip.

  Every Workorder has at least one Attempt, which represents a single
  invocation of the Workflow. If the workflow fails, and the attempt is retried,
  a new Attempt is created on the Workorder.

  This allows you group all the attempts for a single webhook, and track
  the success or failure of a given dataclip.

  ## Creating Workorders

  Workorders can be created in three ways:

  1. Via a webhook trigger
  2. Via a cron trigger
  3. Manually by a user (via the UI or API)

  Retries do not create new Workorders, but rather new Attempts on the existing
  Workorder.
  """

  alias Lightning.Invocation.Dataclip
  alias Lightning.Workflows.Workflow
  alias Lightning.Accounts.User
  alias Lightning.Jobs.Job
  alias Lightning.Jobs.Trigger
  alias Lightning.Repo
  alias Lightning.WorkOrder
  alias Lightning.Attempt
  alias Lightning.{Attempts, Graph}

  import Ecto.Changeset
  import Lightning.Validators
  import Ecto.Query

  @type work_order_option ::
          {:workflow, Workflow.t()}
          | {:dataclip, Dataclip.t()}
          | {:created_by, User.t()}

  # @doc """
  # Create a new Workorder.
  #
  # **For a webhook**
  #     create(trigger, workflow: workflow, dataclip: dataclip)
  #
  # **For a user**
  #     create(job, workflow: workflow, dataclip: dataclip, user: user)
  # """
  @spec create_for(Trigger.t() | Job.t(), [work_order_option()]) ::
          {:ok, WorkOrder.t()} | {:error, Ecto.Changeset.t(WorkOrder.t())}
  def create_for(%Trigger{} = trigger, opts) do
    build_for(trigger, opts |> Map.new())
    |> Repo.insert()
  end

  def create_for(%Job{} = job, opts) do
    build_for(job, opts |> Map.new())
    |> Repo.insert()
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

  This will create a new Attempt on the Workorder, and enqueue it for
  processing.

  When creating a new Attempt, a graph of the workflow is created, and
  using that graph the runs would not be replaced with the new runs are linked.

  For example, by retrying a run from the middle of the workflow, the new
  attempt will only contain the runs that are upstream of the run being
  retried.
  """
  @spec retry(Attempt.t() | Ecto.UUID.t(), Run.t() | Ecto.UUID.t(), [
          work_order_option()
        ]) ::
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

    Attempt.new()
    |> put_assoc(:created_by, attrs[:created_by])
    |> put_assoc(:work_order, attempt.work_order)
    |> put_change(:dataclip_id, run.input_dataclip_id)
    |> put_assoc(:work_order, attempt.work_order)
    |> put_assoc(:starting_job, run.job)
    |> put_assoc(:runs, runs)
    |> validate_required(:dataclip_id)
    |> validate_required_assoc(:work_order)
    |> validate_required_assoc(:created_by)
    |> Attempts.enqueue()
  end

  def retry(attempt, run, opts) do
    retry(attempt.id, run.id, opts)
  end

  @doc """
  Get a Workorder by id.

  Optionally preload associations by passing a list of atoms to `:include`.

      Lightning.WorkOrders.get(id, include: [:attempts])
  """
  @spec get(Ecto.UUID.t(), [{:include, [atom()]}]) :: %WorkOrder{} | nil
  def get(id, opts \\ []) do
    preloads = opts |> Keyword.get(:include, [])

    from(w in WorkOrder,
      where: w.id == ^id,
      preload: ^preloads
    )
    |> Repo.one()
  end
end
