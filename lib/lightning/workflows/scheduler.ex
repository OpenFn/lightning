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
    |> Enum.each(&safe_invoke_cronjob/1)
  end

  # Wraps invoke_cronjob/1 so a failure on a single edge does not abort the
  # rest of the tick. Errors are logged and forwarded to Sentry; the loop
  # continues with the next edge.
  #
  # Why `rescue` only:
  #   - `rescue` covers all database and changeset exceptions.
  #   - `Repo.rollback/1` uses `throw`, but it's consumed by the surrounding
  #     `Repo.transaction(multi)` in `Runs.enqueue/1` — it never reaches here.
  #   - `:exit` signals (DB pool death, supervisor restart) should propagate
  #     to Oban's failure surface, not get swallowed here with N Sentry copies.
  #   - `:throw` from outside Ecto's rollback flow is a control-flow bug
  #     we want visible, not swallowed.
  @spec safe_invoke_cronjob(Edge.t()) :: {:ok, map()} | {:error, term()}
  defp safe_invoke_cronjob(%Edge{} = edge) do
    invoke_cronjob(edge)
  rescue
    e ->
      stacktrace = __STACKTRACE__

      Logger.error(
        "Scheduler failed to invoke cronjob for edge #{edge.id}:\n" <>
          Exception.format(:error, e, stacktrace)
      )

      Lightning.Sentry.capture_exception(e,
        stacktrace: stacktrace,
        extra: %{
          edge_id: edge.id,
          trigger_id: edge.source_trigger && edge.source_trigger.id,
          job_id: edge.target_job && edge.target_job.id,
          workflow_id:
            edge.target_job && edge.target_job.workflow &&
              edge.target_job.workflow.id
        },
        tags: %{type: "scheduler"}
      )

      {:error, e}
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
