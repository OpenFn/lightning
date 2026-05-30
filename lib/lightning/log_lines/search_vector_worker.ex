defmodule Lightning.LogLines.SearchVectorWorker do
  @moduledoc """
  Asynchronously backfills `log_lines.search_vector` for rows that were left
  `NULL` at insert time.

  ## Why defer the tsvector?

  Computing the full-text `search_vector` synchronously (via an insert trigger)
  put `to_tsvector` on the hot path of every log line write. Under heavy run
  load that work serialises behind the worker's log firehose and slows
  ingestion. A sibling migration removes the synchronous trigger, leaving the
  column `NULL` on insert, and adds:

    * a `safe_to_tsvector(regconfig, text)` SQL function (tolerant of bad input);
    * a partial index `... WHERE search_vector IS NULL` so finding pending rows
      stays cheap.

  This worker then fills `search_vector` out-of-band. The read side
  (`Lightning.Invocation`) queries with `to_tsquery('english_nostop', ...)`, so
  this worker MUST build vectors with the matching `english_nostop` config,
  otherwise searches would silently miss freshly-written log lines.

  ## Draining and snowballing

  Each run drains pending rows in bounded batches (`@batch_size` rows, up to
  `@max_batches` per run). When a run consumes its full budget there is almost
  certainly more backlog, so it enqueues an immediate follow-up job (a
  "snowball") rather than waiting for the next 1-minute cron tick. This lets the
  worker keep pace with bursty load while the dedicated `search_indexing` queue
  (concurrency 1) plus job uniqueness keep the snowball self-limiting.

  The cron entry enqueues with default args; the snowball uses
  `%{"trigger" => "snowball"}`. The differing `trigger` key produces a distinct
  uniqueness key, so a queued snowball is never swallowed by the cron job (and
  vice versa).
  """

  use Oban.Worker,
    queue: :search_indexing,
    priority: 1,
    max_attempts: 10,
    unique: [period: 55, keys: [:trigger]]

  alias Lightning.Repo

  require Logger

  # Rows to fill per batch.
  @batch_size 2_500
  # Maximum batches to drain in a single run (per-run budget).
  @max_batches 10

  @drain_sql """
  WITH pending AS (
    SELECT id, run_id FROM log_lines
    WHERE search_vector IS NULL
    ORDER BY timestamp DESC
    LIMIT $1 FOR UPDATE SKIP LOCKED
  )
  UPDATE log_lines l
  SET search_vector = safe_to_tsvector('public.english_nostop'::regconfig, l.message)
  FROM pending p WHERE l.id = p.id AND l.run_id = p.run_id
  """

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    {filled, budget_exhausted?} = drain(0, 0)

    Logger.info(fn ->
      # coveralls-ignore-start
      "LogLines.SearchVectorWorker filled #{filled} search_vector row(s)."
      # coveralls-ignore-stop
    end)

    if budget_exhausted? do
      # The run hit its per-run budget, so more backlog almost certainly
      # remains. Snowball an immediate follow-up with a distinct uniqueness key
      # so the cron job's uniqueness does not swallow it.
      Oban.insert(Lightning.Oban, __MODULE__.new(%{"trigger" => "snowball"}))
    end

    {:ok, filled}
  end

  # Drains up to @max_batches batches, accumulating the number of rows filled.
  # Returns {filled, budget_exhausted?}. Stops early when a batch fills fewer
  # than @batch_size rows (backlog drained).
  defp drain(filled, batches) when batches >= @max_batches do
    {filled, true}
  end

  defp drain(filled, batches) do
    %{num_rows: num_rows} = Repo.query!(@drain_sql, [@batch_size])

    if num_rows < @batch_size do
      {filled + num_rows, false}
    else
      drain(filled + num_rows, batches + 1)
    end
  end
end
