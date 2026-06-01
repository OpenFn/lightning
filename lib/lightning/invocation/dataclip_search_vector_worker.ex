defmodule Lightning.Invocation.DataclipSearchVectorWorker do
  @moduledoc """
  Backfills the full-text `search_vector` on `dataclips` rows.

  Dataclips are inserted with `search_vector` left `NULL`; the vector is built
  here rather than on the insert path. Building it inline was risky:
  `jsonb_to_tsvector` over a large dataclip body is slow and runs inside the
  transaction that persists the run, so a slow (or failing) vector build could
  roll back the dataclip insert and lose the run (#4800). Deferring it keeps
  `jsonb_to_tsvector` off that hot path. Search is eventually consistent as a
  result, typically catching up within a minute.

  Two database objects support this: `safe_jsonb_to_tsvector(regconfig, jsonb)`,
  which builds the vector from the dataclip body while tolerating NULL and
  oversized input, and a partial index over `search_vector IS NULL`, which keeps
  locating pending rows cheap as the table grows. Vectors use the
  `english_nostop` config to match the read side (`Lightning.Invocation`), which
  queries with `to_tsquery('english_nostop', ...)`.

  Each run drains pending rows newest-first, in batches of `@batch_size` up to
  `@max_batches` per run. A run that exhausts its budget leaves backlog behind
  and enqueues an immediate follow-up ("snowball"); otherwise the minute-ly cron
  tick keeps pace. The worker shares the `search_indexing` queue with
  `Lightning.LogLines.SearchVectorWorker`; that queue runs at concurrency 2, so
  the two workers each get a slot and their snowball chains never starve one
  another. The cron tick and the snowball carry distinct `trigger` args, so job
  uniqueness allows one of each to queue but never a duplicate.
  """

  use Oban.Worker,
    queue: :search_indexing,
    priority: 1,
    max_attempts: 10,
    # Restrict uniqueness to queued states. Oban's defaults also dedup against
    # :executing/:completed, so a running snowball would match itself and fail
    # to enqueue its successor — breaking the chain after one hop.
    unique: [period: 55, keys: [:trigger], states: [:available, :scheduled]]

  alias Lightning.Repo

  require Logger

  @batch_size 2_500
  # Per-run budget.
  @max_batches 10

  @drain_sql """
  WITH pending AS (
    SELECT id FROM dataclips
    WHERE search_vector IS NULL
    ORDER BY inserted_at DESC
    LIMIT $1 FOR UPDATE SKIP LOCKED
  )
  UPDATE dataclips d
  SET search_vector =
    safe_jsonb_to_tsvector('public.english_nostop'::regconfig, d.body)
  FROM pending p WHERE d.id = p.id
  """

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    {filled, budget_exhausted?} = drain(0, 0)

    Logger.info(fn ->
      # coveralls-ignore-start
      "Invocation.DataclipSearchVectorWorker filled #{filled} search_vector row(s)."
      # coveralls-ignore-stop
    end)

    if budget_exhausted? do
      # Budget exhausted, so backlog likely remains: enqueue an immediate
      # follow-up rather than waiting for the next cron tick.
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
