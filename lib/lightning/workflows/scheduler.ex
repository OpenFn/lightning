defmodule Lightning.Workflows.Scheduler do
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

  alias Lightning.Invocation
  alias Lightning.Workflows
  alias Lightning.Workflows.Edge
  alias Lightning.WorkOrders

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{}), do: enqueue_cronjobs()

  @doc """
  Find and start any cronjobs that are scheduled to run for a given time
  (defaults to the current time).
  """
  @spec enqueue_cronjobs(DateTime.t()) :: :ok
  def enqueue_cronjobs, do: enqueue_cronjobs(DateTime.utc_now())

  def enqueue_cronjobs(date_time) do
    date_time
    |> Workflows.get_edges_for_cron_execution()
    |> Enum.each(&invoke_cronjob/1)
  end

  @spec invoke_cronjob(Edge.t()) :: {:ok, map()} | {:error, map()}
  defp invoke_cronjob(%Edge{target_job: job, source_trigger: trigger}) do
    with %{project_id: project_id} <- job.workflow,
         :ok <- WorkOrders.limit_run_creation(project_id) do
      dataclip = Invocation.get_next_cron_run_dataclip(trigger)

      case dataclip do
        nil ->
          Logger.debug(fn ->
            # coveralls-ignore-start
            "Starting cronjob #{job.id} for the first time. (No previous final state.)"
            # coveralls-ignore-stop
          end)

          WorkOrders.create_for(trigger,
            dataclip: %{
              type: :global,
              body: %{},
              project_id: project_id
            },
            workflow: job.workflow
          )

        dataclip ->
          Logger.debug(fn ->
            # coveralls-ignore-start
            "Starting cronjob #{job.id} using the final state of its last successful execution."
            # coveralls-ignore-stop
          end)

          WorkOrders.create_for(trigger,
            dataclip: dataclip,
            workflow: job.workflow
          )
      end
    end
  end
end
