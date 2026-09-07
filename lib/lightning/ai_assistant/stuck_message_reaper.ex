defmodule Lightning.AiAssistant.StuckMessageReaper do
  @moduledoc """
  Marks AI chat messages abandoned in `:processing` as errored.

  A message is left `:processing` forever when its job dies without emitting
  telemetry. The main case is a deploy: Oban's watchman gives up after the
  grace period, stops the producer, and only then kills the running task - so
  the handler that would have reported it is already gone.

  Until something clears it the panel stays locked for everyone in that
  session, and nothing raises. `processing_started_at` is written when a
  message starts; this is what reads it.
  """

  use Oban.Worker,
    queue: :background,
    priority: 1,
    max_attempts: 3,
    unique: [period: 290]

  import Ecto.Query

  alias Lightning.AiAssistant.ChatMessage
  alias Lightning.AiAssistant.MessageProcessor
  alias Lightning.Repo

  require Logger

  @worker "Lightning.AiAssistant.MessageProcessor"
  @live_states ~w(available scheduled executing retryable)
  @message "The assistant was interrupted before it finished. Please try again."
  @batch_size 200

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    cutoff =
      DateTime.utc_now()
      |> DateTime.add(-grace_period_ms(), :millisecond)

    candidates = stale_messages(cutoff)

    # Read the live set after the candidates, never before: a job that starts
    # in between appears here and is skipped, whereas the other order could
    # reap a message whose job had only just begun.
    live = live_message_ids(cutoff)

    candidates
    |> Enum.reject(&MapSet.member?(live, &1.id))
    |> Enum.each(&reap/1)

    :ok
  end

  defp stale_messages(cutoff) do
    from(m in ChatMessage,
      where: m.status == :processing,
      where: m.processing_started_at < ^cutoff,
      order_by: [asc: m.processing_started_at],
      # Bounded because each one reaped loads its whole session to tell the
      # panel. The backlog this worker exists for is exactly when that would
      # be largest, and it runs on a single-slot queue; the oldest go first
      # and the rest wait five minutes.
      limit: @batch_size,
      select: %{id: m.id, chat_session_id: m.chat_session_id}
    )
    |> Repo.all()
  end

  # Well clear of the longest a run can legitimately take, so a slow answer is
  # never mistaken for an abandoned one.
  defp grace_period_ms, do: MessageProcessor.job_timeout() + :timer.minutes(2)

  defp live_message_ids(cutoff) do
    from(j in Oban.Job,
      where: j.worker == ^@worker and j.state in ^@live_states,
      # An executing row only means the job is alive while it is fresh. Oban
      # leaves the row executing when a node dies mid-job, and nothing here
      # moves it out again: Cron is the only plugin configured, and Lifeline
      # is what would rescue it. Counting a stale one as live would let an
      # orphaned row shield its message from every future sweep, which is the
      # exact case this worker exists to catch.
      where: j.state != "executing" or j.attempted_at >= ^cutoff,
      select: fragment("?->>'message_id'", j.args)
    )
    |> Repo.all()
    |> MapSet.new()
  end

  defp reap(%{id: id, chat_session_id: session_id}) do
    now = DateTime.utc_now()

    # Guarded update rather than a read-modify-write, so a job that finishes
    # between the select above and this write keeps its own result.
    {count, _} =
      from(m in ChatMessage, where: m.id == ^id and m.status == :processing)
      |> Repo.update_all(
        set: [
          status: :error,
          failure_category: :abandoned,
          failure_message: @message,
          processing_completed_at: now,
          updated_at: now
        ]
      )

    if count == 1 do
      Logger.warning(
        "[AI Assistant] Reaped abandoned message #{id} (session #{session_id})"
      )

      MessageProcessor.broadcast_message_error(session_id, id)
    end
  end
end
