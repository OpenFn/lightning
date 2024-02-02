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
  alias Lightning.Repo
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

        WorkOrders.create_for(trigger,
          dataclip: %{
            type: :global,
            body: %{},
            project_id: job.workflow.project_id
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

  defp last_state_for_job(id) do
    step =
      %Workflows.Job{id: id}
      |> Invocation.Query.last_successful_step_for_job()
      |> Repo.one()

    case step do
      nil -> nil
      step -> Invocation.get_output_dataclip_query(step) |> Repo.one()
    end
  end
end
