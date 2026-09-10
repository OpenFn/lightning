defmodule Lightning.Workflows.Stats do
  @moduledoc """
  Stats for a single workflow, shaped for the workflow health page.

  One public function per chart, each returning only what that chart draws, so a
  cheap chart renders without waiting on an expensive one.

  A failed work order is attributed to every failing step of its latest run, so
  a run that broke in two branches is a row in both. Each row counts work
  orders, not steps, which means the rows can sum past the failure total the
  donuts draw.

  Deliberately independent of `Lightning.DashboardStats`, which serves the
  workflow list view: it batches across many workflows to avoid an N+1 while
  this page queries one, and it collapses every failure state into a single
  `:failed` bucket — the granularity both donuts need apart.
  """
  import Ecto.Query

  alias Lightning.Invocation.Query
  alias Lightning.Invocation.Step
  alias Lightning.Repo
  alias Lightning.Run
  alias Lightning.RunStep
  alias Lightning.Workflows.Snapshot
  alias Lightning.Workflows.Workflow
  alias Lightning.WorkOrder

  @default_days_back 30

  # Caps what the marker cannot see — the window rolling, the retention purge —
  # and stops keys piling up.
  @ttl :timer.minutes(5)

  @final_states WorkOrder.final_states()
  @zero_counts Map.new(@final_states, &{&1, 0})

  @doc """
  Work order counts by final state over the last `days_back` days.
  """
  def outcomes(%Workflow{id: workflow_id}, days_back \\ @default_days_back)
      when days_back > 0 do
    cached({:outcomes, workflow_id, days_back}, fn ->
      window = window(days_back)
      %{window: window, counts: count_work_orders(workflow_id, window.from)}
    end)
  end

  # Every final state is reported and zero-filled, so both donuts read the same
  # aggregate two ways without a second round trip. The window is anchored on
  # `last_activity`, not `inserted_at`: an old work order retried today is
  # counted as the work it currently is.
  defp count_work_orders(workflow_id, since) do
    from(wo in WorkOrder,
      where:
        wo.workflow_id == ^workflow_id and wo.last_activity > ^since and
          wo.state in ^@final_states,
      group_by: wo.state,
      select: {wo.state, count(wo.id)}
    )
    |> Repo.all()
    |> Enum.into(@zero_counts)
  end

  @doc """
  Failed work orders grouped by error signature over the last `days_back` days.

  The signature's parts are returned separately rather than as one string: the
  table styles each part differently, and the tip is looked up by `error_type`.

  A count is the number of work orders that hit that signature, so a work order
  that failed in two branches is counted once under each. That makes the rows
  sum past the failure total the outcomes donut draws, which is the trade: a
  second broken branch is its own thing to fix, not fallout from the first.
  """
  def error_signatures(
        %Workflow{id: workflow_id},
        days_back \\ @default_days_back
      )
      when days_back > 0 do
    cached({:failures, workflow_id, days_back}, fn ->
      window = window(days_back)

      %{
        window: window,
        signatures: group_by_signature(workflow_id, window.from)
      }
    end)
  end

  # How the runs chart slices each window: `{bucket_seconds, bucket_count}`.
  # Every width divides a day evenly, so a window whose `from` sits on the grid
  # keeps every bucket boundary on the clock — 2-hourly, AM/PM, midnight.
  #
  # One bucket more than the width divides into: `now` sits mid-bucket, so a
  # grid of exactly `days_back / width` bars would start *after*
  # `now - days_back` and leave the oldest hours of the window undrawn while
  # the donuts beside it counted them. The oldest bar instead reaches back
  # past `from`, and `window` reports the range actually covered.
  @buckets %{1 => {7_200, 13}, 7 => {43_200, 15}, 30 => {86_400, 31}}

  @zero_run_counts Map.new(Run.final_states(), &{&1, 0})

  @typedoc "One bar of the runs chart: when its slot starts, and its counts."
  @type run_bucket :: %{
          :at => DateTime.t(),
          optional(atom()) => non_neg_integer()
        }

  @doc """
  Final run counts per state, bucketed across the last `days_back` days:
  2-hourly over a day, AM/PM over a week, daily over a month.

  Bucketed here rather than in the browser, because the alternative is shipping
  every run in the window — six figures of rows on a busy workflow, cached
  whole and JSON-encoded — to draw thirty bars.

  Buckets are counted on `inserted_at` — when the attempt started, not when it
  settled — so a run stays in the bar the traffic arrived in. Every bucket and
  every state is present, zero-filled: the chart draws a flat window without
  reasoning about which bars are missing.

  The last bucket is the one `now` falls in, so it is still filling; the first
  reaches back past `now - days_back`, so nothing in the window goes undrawn.
  `window` is the range the bars actually cover.

  A bucket is `at` alongside one key per state, flat rather than nested, which
  is the row shape Recharts takes as `data` — the list goes to the chart
  untouched, and each `Bar` names the state it draws.
  """
  @spec runs(Workflow.t(), 1 | 7 | 30) :: %{
          window: %{from: DateTime.t(), to: DateTime.t()},
          buckets: [run_bucket()]
        }
  def runs(%Workflow{id: workflow_id}, days_back \\ @default_days_back)
      when is_map_key(@buckets, days_back) do
    cached({:runs, workflow_id, days_back}, fn ->
      {seconds, count} = Map.fetch!(@buckets, days_back)
      window = bucket_window(seconds, count)

      %{
        window: window,
        buckets: bucket_runs(workflow_id, window.from, seconds, count)
      }
    end)
  end

  # Anchored on the bucket `now` is in, not on `now` itself: a window that ends
  # mid-bucket would put every boundary at whatever minute the request landed
  # on, and the labels the chart draws — "2am", "PM", a date — would be lies.
  defp bucket_window(seconds, count) do
    to = DateTime.utc_now()
    current = DateTime.from_unix!(div(DateTime.to_unix(to), seconds) * seconds)

    %{from: DateTime.add(current, -(count - 1) * seconds, :second), to: to}
  end

  defp bucket_runs(workflow_id, from, seconds, count) do
    tallies = tally_runs(workflow_id, from, seconds)

    Enum.map(0..(count - 1), fn index ->
      tallies
      |> Map.get(index, [])
      |> Enum.into(@zero_run_counts)
      |> Map.put(:at, DateTime.add(from, index * seconds, :second))
    end)
  end

  # `wo.last_activity` is redundant against the run filter — a work order is
  # touched every time one of its runs is created or settles, so its activity
  # is never older than its newest run. It is here for the planner: it lets the
  # `work_orders(workflow_id, last_activity)` index cut the work orders down to
  # the window before the nested loop into `runs(work_order_id, inserted_at)`,
  # instead of probing every work order the workflow ever had.
  #
  # The grid is aligned, so integer division by the bucket width is the whole
  # of the bucketing — no `date_trunc` special case per width. `floor` before
  # the cast because `extract` yields `numeric` and `numeric::bigint` rounds:
  # without it a run at 01:59:59.7 is counted in the 02:00 bar.
  defp tally_runs(workflow_id, from, seconds) do
    from(r in Run,
      join: wo in WorkOrder,
      on: wo.id == r.work_order_id,
      where:
        wo.workflow_id == ^workflow_id and wo.last_activity >= ^from and
          r.inserted_at >= ^from and r.state in ^Run.final_states(),
      group_by: [selected_as(:bucket), r.state],
      select: {
        selected_as(
          fragment(
            "div(floor(extract(epoch from ? - ?))::bigint, ?)::int",
            r.inserted_at,
            type(^from, :utc_datetime_usec),
            type(^seconds, :integer)
          ),
          :bucket
        ),
        r.state,
        count(r.id)
      }
    )
    |> Repo.all()
    |> Enum.group_by(fn {bucket, _, _} -> bucket end, fn {_, state, count} ->
      {state, count}
    end)
  end

  defp window(days_back) do
    to = DateTime.utc_now()
    %{from: DateTime.add(to, -days_back, :day), to: to}
  end

  # Cached whole, `window` included — that is what stops the window rolling per
  # request.
  #
  # The marker goes in the key rather than the cache being invalidated when
  # something settles: a poll that finds nothing has moved is a hit on every
  # pod, because the answer is read from Postgres and not from one node's ETS.
  # The trade is that a workflow settling work orders faster than the poll
  # recomputes on every poll.
  #
  # The marker only moves when a work order settles, so a stat counting unsettled
  # work orders — a queue depth, a running count — needs its own marker.
  #
  # Every key must map to exactly one computation. Cachex tracks a fetch in
  # flight by key alone and ignores the fallback closure
  # (`deps/cachex/lib/cachex/services/courier.ex:60-62`), so a second caller
  # with a different closure for the same key never runs its own and is handed
  # the first one's answer. `outcomes/2` and `error_signatures/2` are safe
  # because their key prefixes differ.
  defp cached({_slice, workflow_id, _days} = key, fun) do
    key = Tuple.insert_at(key, 3, change_marker(workflow_id))

    case Cachex.fetch(:workflow_stats, key, fn ->
           {:commit, fun.(), expire: @ttl}
         end) do
      {tag, value} when tag in [:ok, :commit] ->
        value

      # Cachex rescues whatever the fallback raised and hands it back as a
      # value. Reraised with its original stack, Sentry gets the DB failure
      # that actually happened instead of a `CaseClauseError` on a tuple.
      {:error, %Cachex.Error{stack: stack} = error} ->
        reraise error, stack

      {:error, reason} ->
        raise "workflow stats cache failed: #{inspect(reason)}"
    end
  end

  # Only settled work orders move the marker, because only settled work orders
  # are counted. `last_activity` moves when a run merely starts, so an
  # unfiltered max would recompute for every open tab on every poll of a
  # workflow with a cron.
  #
  # The gap is a work order that is not final while something it holds already
  # is — a retry, or a run that settles while a sibling is still in flight. That
  # work order stops counting until it settles, or until the entry expires.
  #
  # Indexed as `(workflow_id, last_activity)`, so this is a lookup, not a scan.
  defp change_marker(workflow_id) do
    Repo.one(
      from(wo in WorkOrder,
        where: wo.workflow_id == ^workflow_id and wo.state in ^@final_states,
        select: max(wo.last_activity)
      )
    )
  end

  # One row per failing step of the work order's latest run — the run whose
  # completion set the work order's state.
  #
  # The lateral join is what expresses "every failing step, or one empty row if
  # the run never reached one": a plain `left_join` would emit an empty row per
  # step that succeeded, and an inner join would drop the work orders — lost,
  # crashed, rejected — that have no step to speak for them.
  defp attributed_failures(workflow_id, since) do
    failing_steps =
      from(s in Step,
        join: rs in RunStep,
        on: rs.step_id == s.id,
        where: rs.run_id == parent_as(:latest_run).run_id,
        select: %{
          exit_reason: s.exit_reason,
          # `""` is the same "we were not told" as NULL, but it groups apart
          # and, being truthy, masks the run's own type in `to_signature/2`.
          error_type: fragment("NULLIF(?, '')", s.error_type),
          snapshot_id: s.snapshot_id,
          job_id: s.job_id
        }
      )
      |> Query.where_step_failed()

    from(lr in subquery(latest_runs(workflow_id, since)),
      as: :latest_run,
      left_lateral_join: s in subquery(failing_steps),
      on: true,
      select: %{
        work_order_id: lr.work_order_id,
        work_order_state: lr.work_order_state,
        run_state: lr.run_state,
        run_error_type: lr.run_error_type,
        exit_reason: s.exit_reason,
        error_type: s.error_type,
        snapshot_id: s.snapshot_id,
        job_id: s.job_id
      }
    )
  end

  # The latest run only, so a work order retried into a second failure is not
  # described twice — by the attempt that set its state and by the one before.
  defp latest_runs(workflow_id, since) do
    from(wo in WorkOrder,
      # left_join, not join: a rejected work order has no run and still counts.
      left_join: r in Run,
      as: :run,
      on: r.work_order_id == wo.id,
      where:
        wo.workflow_id == ^workflow_id and wo.last_activity > ^since and
          wo.state in ^WorkOrder.failure_states(),
      distinct: wo.id,
      order_by: [asc: wo.id],
      select: %{
        work_order_id: wo.id,
        work_order_state: wo.state,
        run_id: r.id,
        run_state: r.state,
        run_error_type: fragment("NULLIF(?, '')", r.error_type)
      }
    )
    |> Query.order_by_run_recency()
  end

  # The job's name and adaptor come off the run's own snapshot, not the live
  # `jobs` table, so a job since deleted is still nameable. The label a merged
  # group ends up with is the newest failing snapshot's — see `merge_group/1`.
  # Resolving after the group keeps the jsonb unnest down to the few snapshots
  # that actually failed in the window — joining it in would unnest every
  # snapshot the workflow ever had.
  defp group_by_signature(workflow_id, since) do
    rows =
      from(a in subquery(attributed_failures(workflow_id, since)),
        group_by: [
          a.work_order_state,
          a.exit_reason,
          a.error_type,
          a.run_state,
          a.run_error_type,
          a.snapshot_id,
          a.job_id
        ],
        select: %{
          work_order_state: a.work_order_state,
          exit_reason: a.exit_reason,
          error_type: a.error_type,
          run_state: a.run_state,
          run_error_type: a.run_error_type,
          snapshot_id: a.snapshot_id,
          job_id: a.job_id,
          count: count(a.work_order_id, :distinct)
        }
      )
      |> Repo.all()

    jobs =
      rows
      |> Enum.map(& &1.snapshot_id)
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()
      |> snapshot_jobs()

    rows
    |> Enum.map(&to_signature(&1, jobs))
    |> merge_counts()
  end

  # Keyed by snapshot as well as job, because the same job id carries a
  # different name in every snapshot that renamed it. `lock_version` rides
  # along for `merge_counts/1` to pick a label with, since a snapshot's own id
  # carries no timestamp to compare rows by — it is unique and monotonic per
  # workflow, so the highest one read is the most recent. Only these three
  # fields are read out, so the job bodies alongside them never cross the
  # wire.
  defp snapshot_jobs([]), do: %{}

  defp snapshot_jobs(snapshot_ids) do
    from(s in Snapshot,
      where: s.id in ^snapshot_ids,
      cross_lateral_join: j in fragment("jsonb_array_elements(?)", s.jobs),
      select:
        {{s.id, fragment("? ->> ?", j, "id")},
         {fragment("? ->> ?", j, "name"), fragment("? ->> ?", j, "adaptor"),
          s.lock_version}}
    )
    |> Repo.all()
    |> Map.new()
  end

  # A rejected work order never got a run, so there is no signature to read.
  # `:rejected` has one origin — the run limit refusing a webhook payload — so
  # the label names it outright. `job_id: nil` gives it the same shape as
  # every other row, for the JSON and the TS type on the other end of it.
  defp to_signature(%{work_order_state: :rejected} = row, _jobs) do
    %{
      count: row.count,
      exit_reason: "rejected",
      error_type: "RunLimitExceeded",
      job_id: nil,
      step_name: nil,
      adaptor: nil
    }
  end

  # A step that finished carries its own reason and error type; one that never
  # reported — a lost or reaped run — carries only the reason, and the rest
  # comes off the run. `mark_steps_lost/1` is why: it stamps `exit_reason` and
  # leaves `error_type` alone.
  #
  # `job_id` is the key `merge_counts/1` folds rows on; `step_name` and
  # `adaptor` are labels, resolved off the snapshot and carried with
  # `lock_version` so the fold can pick the newest one and then drop it.
  defp to_signature(row, jobs) do
    {step_name, adaptor, lock_version} =
      Map.get(jobs, {row.snapshot_id, row.job_id}, {nil, nil, nil})

    %{
      count: row.count,
      exit_reason: exit_reason(row.exit_reason, row.run_state),
      error_type: error_type(row.error_type, row.run_error_type),
      job_id: row.job_id,
      step_name: step_name,
      adaptor: adaptor,
      lock_version: lock_version
    }
  end

  # `mark_steps_lost/1` stamps a step's `exit_reason` and nothing else, so a
  # crashed run with no step at all falls back to `Run.state_reasons/0` — the
  # worker's own words for each terminal state.
  defp exit_reason(step_exit_reason, run_state) do
    step_exit_reason || Map.get(Run.state_reasons(), run_state)
  end

  # An empty string is missing on both sides: `"" || x` returns `""` (empty
  # string is truthy in Elixir), which would split one failure into two
  # identical-looking rows.
  defp error_type(step_error_type, run_error_type) do
    blank_to_nil(step_error_type) || blank_to_nil(run_error_type)
  end

  defp blank_to_nil(""), do: nil
  defp blank_to_nil(other), do: other

  # Two groups can collapse into one signature — a crashed run and a failed run
  # whose steps both reported `fail`, say, or the same job renamed mid-window —
  # so the fold happens after the coalesce, not in the `group_by`. Grouping key
  # is the triple that identifies a failure: the label (`step_name`, `adaptor`)
  # is expected to differ between rows a rename merges, and `lock_version`
  # never repeats.
  defp merge_counts(signatures) do
    signatures
    |> Enum.group_by(&{&1.exit_reason, &1.error_type, &1.job_id})
    |> Enum.map(fn {_key, rows} -> merge_group(rows) end)
    |> Enum.sort_by(&{-&1.count, &1.step_name}, :asc)
  end

  # The label comes from the group's most recent failing snapshot: the row
  # with the highest `lock_version`. A row with no snapshot at all (a rejected
  # work order, or a run that never reached a step) carries no `lock_version`,
  # which sorts lowest and never wins over a labelled one.
  defp merge_group(rows) do
    label = Enum.max_by(rows, &(&1[:lock_version] || -1))

    %{
      count: Enum.sum_by(rows, & &1.count),
      exit_reason: label.exit_reason,
      error_type: label.error_type,
      job_id: label.job_id,
      step_name: label.step_name,
      adaptor: label.adaptor
    }
  end
end
