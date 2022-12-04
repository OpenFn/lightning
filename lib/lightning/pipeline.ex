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
  alias Lightning.Invocation.Run
  alias Lightning.Repo
  alias Lightning.{AttemptService, AttemptRun}
  import Ecto.Query

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"attempt_run_id" => attempt_run_id}}) do
    Repo.get!(AttemptRun, attempt_run_id)
    |> process()
  end

  @spec process(AttemptRun.t()) :: :ok
  def process(%AttemptRun{} = attempt_run) do
    run = Ecto.assoc(attempt_run, :run) |> Repo.one!()
    result = Runner.start(run) |> handle_result()

    jobs = get_jobs_for_result(run.job_id, result)

    if length(jobs) > 0 do
      next_dataclip_id = get_next_dataclip_id(result, run)

      jobs
      |> Enum.map(fn %{id: job_id, workflow: %{project_id: project_id}} ->
        # create a new run for the same attempt
        {:ok, attempt_run} =
          AttemptService.append(
            attempt_run,
            Run.changeset(%Run{}, %{
              job_id: job_id,
              input_dataclip_id: next_dataclip_id,
              project_id: project_id
            })
          )

        new(%{"attempt_run_id" => attempt_run.id})
      end)
      |> Enum.each(&Oban.insert/1)
    end

    :ok
  end

  # This is from a either a timeout, or the outside process being stopped.
  defp handle_result(%Engine.Result{exit_reason: :killed, log: log} = result) do
    timeout_log = [
      "==== TIMEOUT ===================================================================",
      "",
      "We had to abort this run because it took too long. Here's what to do:",
      "",
      " - Check your destination system to ensure it's working and responding properly",
      "   to API requests.",
      " - Check your job expression to make sure you haven't created any infinite loops",
      "   or long sleep/wait commands.",
      "",
      "Only enterprise plans support runs lasting more than 100 seconds.",
      "Contact enterprise@openfn.org to enable long-running jobs."
    ]

    %{result | log: log ++ timeout_log, exit_code: 2}
  end

  # This _shouldn't_ match, although it's possible for a ShellRuntime to
  # exit without a value - that should be considered a bug.
  defp handle_result(%Engine.Result{log: log, exit_code: nil} = result) do
    handle_result(%{
      result
      | exit_code:
          if(Enum.any?(log, &String.contains?(&1, "out of memory")),
            do: 134,
            else: 11
          )
    })
  end

  defp handle_result(%Engine.Result{} = result), do: result

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
    IO.inspect(result, label: "REASON")

    case result.exit_reason do
      :error ->
        run.input_dataclip_id

      :ok ->
        from(d in Invocation.Dataclip,
          join: r in assoc(d, :source_run),
          where: r.id == ^run.id,
          select: d.id
        )
        |> Repo.one()
    end
  end
end
