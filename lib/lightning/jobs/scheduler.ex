defmodule Lightning.Jobs.Scheduler do
  use Oban.Worker,
    queue: :scheduler,
    priority: 1,
    max_attempts: 1,
    # This unqique period ensures that cron jobs are only enqueued once across a cluster
    unique: [period: 59]

  require Logger

  alias Lightning.{
    Invocation,
    Jobs,
    Pipeline,
    Repo
  }

  @impl Oban.Worker
  @spec perform(Oban.Job.t()) :: {:ok, any}
  def perform(%Oban.Job{}),
    do: enqueue_cronjobs(DateTime.utc_now() |> DateTime.to_unix())

  @spec enqueue_cronjobs(any) :: {:ok, [any]}
  def enqueue_cronjobs(now) do
    Jobs.find_cron_triggers(now)
    |> Enum.each(fn %Jobs.Job{id: id, project_id: project_id} ->
      {:ok, %{event: event, run: run}} =
        case last_run_for_job(id) do
          nil ->
            Invocation.create(
              %{job_id: id, project_id: project_id, type: :cron},
              %{type: :empty, body: %{}}
            )

          run ->
            Invocation.create(
              %{job_id: id, project_id: project_id, type: :cron},
              %{
                type: :run_result,
                body:
                  run
                  |> Lightning.Invocation.get_result_dataclip_query()
                  |> Repo.one()
                  |> Map.get(:body)
              }
            )
        end

      Pipeline.new(%{event_id: event.id, run_id: run.id})
      |> Oban.insert()
    end)

    :ok
  end

  defp last_run_for_job(id) do
    Invocation.Query.last_run_for_job(%Jobs.Job{id: id})
    |> Repo.one()
  end

  @spec active_jobs_with_cron_triggers :: any
  def active_jobs_with_cron_triggers do
    Jobs.Query.enabled_cron_jobs()
    |> Repo.all()
  end
end
