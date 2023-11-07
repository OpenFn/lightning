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

  require Logger

  alias Lightning.{
    Invocation,
    Repo,
    WorkOrders,
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
      {:ok, _workorder} = invoke_cronjob(edge)
    end)

    :ok
  end

  @spec invoke_cronjob(Lightning.Workflows.Edge.t()) :: {:ok | :error, map()}
  defp invoke_cronjob(%{target_job: job, source_trigger: trigger} = _edge) do
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

        dataclip =
          %{
            type: :global,
            body: %{},
            project_id: job.workflow.project_id
          }
          |> Dataclip.new()
          |> Repo.insert!()

        WorkOrders.create_for(trigger, %{
          dataclip: dataclip,
          workflow: job.workflow
        })

      dataclip ->
        Logger.debug(fn ->
          # coveralls-ignore-start
          "Starting cronjob #{job.id} using the final state of its last successful run."
          # coveralls-ignore-stop
        end)

        WorkOrders.create_for(trigger, %{
          dataclip: dataclip,
          workflow: job.workflow
        })
    end
  end

  defp last_state_for_job(id) do
    run =
      %Workflows.Job{id: id}
      |> Invocation.Query.last_successful_run_for_job()
      |> Repo.one()

    case run do
      nil -> nil
      run -> Invocation.get_output_dataclip_query(run) |> Repo.one()
    end
  end
end
