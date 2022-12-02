defmodule ObanManager do
  require Logger

  alias OpenFn.{
    Repo,
    Run,
    RunService,
    FlowService,
    ObanQuery
  }

  def handle_event([:oban, :circuit, :open], _measure, meta, _pid),
    do: Logger.info("Circuit open #{inspect(meta, pretty: true)}")

  def handle_event([:oban, :circuit, :trip], _measure, meta, _pid) do
    Logger.error("Circuit tripped with #{inspect(meta, pretty: true)}")

    context =
      Map.take(meta, [:name])
      |> scrub_context

    Sentry.capture_exception(meta.error,
      stacktrace: meta.stacktrace,
      message: meta.message,
      extra: context,
      tags: %{type: "oban"}
    )
  end

  def handle_event([:oban, :job, :exception] = first, measure, meta, _pid) do
    IO.inspect(first, label: "first")
    IO.inspect(measure, label: "measure")
    IO.inspect(meta, label: "meta")

    # Logger.error(~s"""
    # Oban exception:
    # #{inspect(meta.error)}
    # #{Exception.format_stacktrace(meta.stacktrace)}

    # meta:
    #   #{Map.drop(meta, [:error, :stacktrace]) |> inspect(pretty: true)}

    # (#{inspect(measure, pretty: true)})
    # """)

    # context =
    #   meta
    #   |> Map.take([:id, :args, :queue, :worker])
    #   |> Map.merge(measure)
    #   |> scrub_context

    # args = meta.args
    # queue = meta.queue
    # error = meta.error

    # dead? = meta.attempt >= meta.max_attempts
    # timeout? = Map.get(error, :reason) == :timeout

    # if timeout? do
    #   Sentry.capture_message("Processor Timeout",
    #     level: "warning",
    #     message: error,
    #     extra: context,
    #     tags: %{type: "timeout"}
    #   )
    # else
    #   Sentry.capture_exception(error,
    #     stacktrace: meta.stacktrace,
    #     message: error,
    #     error: error,
    #     extra: context,
    #     tags: %{type: "oban"}
    #   )
    # end

    # Note: if this is a failed run, we need to ensure that it gets an exit code
    # and that any subsequent "catch" jobs are initialized. This is done via a
    # task because—at this point—the best we can do is "try" and we don't want
    # to tie up the success of this Oban event handler with the success of our
    # "rescue effort".
    # if dead? && String.contains?(queue, "runs"),
    #   do:
    #     Task.start(__MODULE__, :handle_crashed_run, [
    #       get_in(args, ["run", "id"]),
    #       get_in(args, ["state"]),
    #       error,
    #       timeout?
    #     ])

    # handle_crashed_run(
    #     get_in(args, ["run", "id"]),
    #     get_in(args, ["state"]),
    #     error,
    #     timeout?
    #   )
  end

  @doc """
  Attempt to create a record of the crash, updating an existing run in the db.
  """
  def handle_crashed_run(run_id, state, error, timeout?) do
    # run = Repo.get(Run, run_id)

    # result =
    #   if timeout? do
    #     %Engine.Result{
    #       exit_code: 4,
    #       log: [
    #         "==== TIMEOUT && UNRESPONSIVE ===================================================",
    #         "",
    #         "We had to shut down this run because it timed out and became unresponsive.",
    #         "Here's what to do:",
    #         "",
    #         " - Check your destination system to ensure it's working and responding properly",
    #         "   to API requests.",
    #         " - Check your job expression to make sure you haven't created any infinite loops",
    #         "   or long sleep/wait commands.",
    #         "",
    #         "Only enterprise plans support runs lasting more than 100 seconds.",
    #         "Contact enterprise@openfn.org to enable long-running jobs."
    #       ]
    #     }
    #   else
    #     case error do
    #       %Dispatcher.AdaptorError{message: message, code: nil} ->
    #         %Engine.Result{exit_code: 7, log: [message]}

    #       %Dispatcher.AdaptorError{message: message, code: code, log: log} ->
    #         %Engine.Result{
    #           exit_code: 7,
    #           log:
    #             ~s"""
    #             #{message}:
    #             #{log}

    #             Exited with #{code}
    #             """
    #             |> String.split("\n")
    #         }

    #       _other ->
    #         %Engine.Result{
    #           exit_code: 5,
    #           log: [
    #             "OpenFn encountered an unexpected error during the execution of this job:",
    #             inspect(error, pretty: true)
    #           ]
    #         }
    #     end
    #   end

    # result
    # |> RunService.ensure_result_handled(run)
    # |> FlowService.ensure_flow_controlled(state)
    # |> clean_timeouts_for_run()
  end

  @doc """
  Attempt to create a record of the crash, updating an existing run in the db.
  """
  def handle_orphaned_run(run_id, state) do
    # run = Repo.get(Run, run_id)

    # %Engine.Result{
    #   exit_code: 4,
    #   log: [
    #     "==== LOST CONNECTION TO NODE ===================================================",
    #     "",
    #     "We lost connection to the node that was handling this run. It may have taken",
    #     "longer than the grace period. Here's what to do:",
    #     "",
    #     " - Check your destination system to ensure it's working and responding properly",
    #     "   to API requests.",
    #     " - Check your job expression to make sure you haven't created any infinite loops",
    #     "   or long sleep/wait commands.",
    #     "",
    #     "Only enterprise plans support runs lasting more than 100 seconds.",
    #     "Contact enterprise@openfn.org to enable long-running jobs."
    #   ]
    # }
    # |> RunService.ensure_result_handled(run)
    # |> FlowService.ensure_flow_controlled(state)
  end

  @doc """
  Given a run which we are certain has been handled properly (i.e., exit_code
  has been set, FlowService has been called), clean_timeouts_for_run will remove
  the 'discarded' Oban jobs related to that run from the DB. Normally, discarded
  Oban Jobs stay in the DB to be manually removed during daily reviews, but exit
  code 4 (an unresponsive NodeVM) happens frequently enough that we should
  automate this process. A record of unresponsive VMs can (and should) be
  reviewed to ensure that it happens infrequently, but this decouples that
  process from the normal operation of the platform which, sadly, includes and
  handles unresponsive NodeVMs as part of its standard operating procedure.
  """
  # def clean_timeouts_for_run(%Run{id: id}) do
  #   Logger.warn(
  #     "Deleting discarded ObanJob(s) for Run ##{id}; it failed with Oban.TimeoutError and was handled."
  #   )

  #   ObanQuery.timeouts_for_run(id)
  #   |> Repo.delete_all()
  # end

  # defp scrub_context(context) do
  #   {_private_state, safe_context} = pop_in(context, [:args, "state"])
  #   safe_context
  # end
end
