defmodule Lightning.Pipeline do
  @moduledoc """
  Service class to coordinate the running of jobs, and their downstream jobs.
  """
  use Oban.Worker,
    queue: :runs,
    priority: 1,
    max_attempts: 1

  require Logger

  alias Lightning.Pipeline.Runner

  alias Lightning.{Jobs, Invocation}
  alias Lightning.Invocation.Event
  alias Lightning.Repo
  import Ecto.Query, only: [select: 3]

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"event_id" => id}}) do
    Invocation.Event
    |> Repo.get(id)
    |> process()

    :ok
  end

  @spec process(Event.t()) :: :ok
  def process(%Event{} = event) do
    run = Invocation.get_run!(event)
    result = Runner.start(run)

    jobs = get_jobs_for_result(event.job_id, result)

    if length(jobs) > 0 do
      next_dataclip_id = get_next_dataclip_id(result, run)

      jobs
      |> Enum.map(fn %{id: job_id, project_id: project_id} ->
        %{
          job_id: job_id,
          type: :flow,
          dataclip_id: next_dataclip_id,
          source_id: event.id,
          project_id: project_id
        }
      end)
      |> Enum.map(fn attrs ->
        {:ok, %{event: event}} = Invocation.create(attrs)
        new(%{event_id: event.id})
      end)
      |> Enum.each(&Oban.insert/1)
    end

    :ok
  end

  defp result_to_trigger_type(%Engine.Result{exit_reason: reason}) do
    case reason do
      :error -> :on_job_failure
      :ok -> :on_job_success
      _ -> nil
    end
  end

  defp get_jobs_for_result(upstream_job_id, result) do
    Jobs.get_downstream_jobs_for(upstream_job_id, result_to_trigger_type(result))
  end

  defp get_next_dataclip_id(result, run) do
    case result.exit_reason do
      :error ->
        Invocation.get_dataclip_query(run)
        |> select([d], d.id)
        |> Repo.one()

      :ok ->
        Invocation.get_result_dataclip_query(run)
        |> select([d], d.id)
        |> Repo.one()
    end
  end
end
