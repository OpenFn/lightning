defmodule Lightning.Jobs.Scheduler do
  @moduledoc """
  The Scheduler is responsible for finding jobs that are ready to run based on
  their cron schedule, and then running them.
  """
  use Oban.Worker,
    queue: :scheduler,
    priority: 1,
    max_attempts: 1,
    # This unique period ensures that cron jobs are only enqueued once across a cluster
    unique: [period: 59]

  require Logger

  alias Lightning.{
    Invocation,
    Jobs,
    Pipeline,
    Repo,
    WorkOrderService,
    Workflows
  }

  alias Lightning.Invocation.Dataclip

  @impl Oban.Worker
  def perform(%Oban.Job{}), do: enqueue_cronjobs()

  @doc """
  Find and start any cronjobs that are scheduled to run for a given time
  (defaults to the current time).
  """
  @spec enqueue_cronjobs(DateTime.t()) :: :ok
  def enqueue_cronjobs(), do: enqueue_cronjobs(DateTime.utc_now())

  def enqueue_cronjobs(date_time) do
    date_time
    |> Workflows.get_edges_for_cron_execution()
    |> Enum.each(fn edge ->
      {:ok, %{attempt_run: attempt_run}} = invoke_cronjob(edge)

      Pipeline.new(%{attempt_run_id: attempt_run.id})
      |> Oban.insert()
    end)

    :ok
  end

  @spec invoke_cronjob(Lightning.Workflows.Edge.t()) :: {:ok | :error, map()}
  defp invoke_cronjob(%{target_job: job} = edge) do
    case last_state_for_job(job.id) do
      nil ->
        Logger.debug(fn ->
          # coveralls-ignore-start
          "Starting cronjob #{job.id} for the first time. (No previous final state.)"
          # coveralls-ignore-stop
        end)

        # Add a facility to specify _which_ global state should be use as
        # the first initial state for a cron-triggered job.
        # The implementation would look like:
        # default_state_for_job(id)
        # %{id: uuid, type: :global, body: %{arbitrary: true}}
        WorkOrderService.multi_for(
          :cron,
          edge,
          Dataclip.new(%{
            type: :global,
            body: %{},
            project_id: job.workflow.project_id
          })
        )
        |> Repo.transaction()

      dataclip ->
        Logger.debug(fn ->
          # coveralls-ignore-start
          "Starting cronjob #{job.id} using the final state of its last successful run."
          # coveralls-ignore-stop
        end)

        WorkOrderService.multi_for(:cron, edge, dataclip)
        |> Repo.transaction()
    end
  end

  defp last_state_for_job(id) do
    run =
      %Jobs.Job{id: id}
      |> Invocation.Query.last_successful_run_for_job()
      |> Repo.one()

    case run do
      nil -> nil
      run -> Invocation.get_result_dataclip_query(run) |> Repo.one()
    end
  end
end
