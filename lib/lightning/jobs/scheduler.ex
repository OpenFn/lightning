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
    WorkOrderService
  }

  alias Lightning.Invocation.Dataclip

  @impl Oban.Worker
  def perform(%Oban.Job{}), do: enqueue_cronjobs()

  @doc """
  Find and start any cronjobs that are scheduled to run for a given time
  (defaults to the current time).
  """
  def enqueue_cronjobs(date_time \\ DateTime.utc_now()) do
    date_time
    |> DateTime.to_unix()
    |> Jobs.get_jobs_for_cron_execution()
    |> Enum.each(fn job ->
      {:ok, %{event: event, run: _run}} = invoke_cronjob(job)

      Pipeline.new(%{event_id: event.id})
      |> Oban.insert()
    end)

    :ok
  end

  @spec invoke_cronjob(Lightning.Jobs.Job.t()) :: {:ok | :error, map()}
  defp invoke_cronjob(job) do
    case last_state_for_job(job.id) do
      nil ->
        Logger.debug(fn ->
          "Starting cronjob #{job.id} for the first time. (No previous final state.)"
        end)

        # Add a facility to specify _which_ global state should be use as
        # the first initial state for a cron-triggered job.
        # The implementation would look like:
        # default_state_for_job(id)
        # %{id: uuid, type: :global, body: %{arbitrary: true}}
        WorkOrderService.multi_for(
          :cron,
          job,
          Dataclip.new(%{
            type: :global,
            body: %{},
            project_id: job.workflow.project_id
          })
        )
        |> Repo.transaction()

      dataclip ->
        Logger.debug(fn ->
          "Starting cronjob #{job.id} using the final state of its last successful run."
        end)

        WorkOrderService.multi_for(:cron, job, dataclip)
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

  @spec active_jobs_with_cron_triggers :: any
  def active_jobs_with_cron_triggers do
    Jobs.Query.enabled_cron_jobs()
    |> Repo.all()
  end
end
