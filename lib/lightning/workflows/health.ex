defmodule Lightning.Workflows.Health do
  @moduledoc """
  Aggregate queries backing the workflow health screen.

  Every function takes a workflow and a time window, and answers one question
  about the runs that started inside that window.

  `load/3` is the entry point the screen uses. It reads each underlying record
  set exactly once and derives several panels from each read — run states feed
  both the outcomes donut and the failure breakdown, and failure signatures
  feed both the triage list and the per-step bars. The single-panel functions
  are kept public for callers that want one number, and each runs its own
  query.

  ## What is real and what is not

  Most of this screen is backed by columns we already store: `Run.state`,
  `Step.exit_reason`, `Step.error_type` and the various timestamps.

  The one gap is the error *message*, and it is closer than it looks. The
  worker sends one with every step result and `Lightning.Runs.Handlers` carries
  it as far as `to_step_params/1`, where Ecto drops it because `Step` has no
  `error_message` column — see the deferred field at
  `Lightning.Invocation.Step`. The same text is persisted in `LogLine`, so
  nothing is lost, but it is not on a column we can group by.

  Until that field exists, a true error signature — the thing that lets you say
  "these 62 runs all hit the same bug" — cannot be computed. `triage/3` groups
  by the coarsest real signature available (blame, exit reason, error type,
  step) and marks each group as having no message.
  """

  import Ecto.Query

  alias Lightning.Invocation.Step
  alias Lightning.Repo
  alias Lightning.Run
  alias Lightning.RunStep
  alias Lightning.Workflows.Workflow
  alias Lightning.WorkOrder

  @histogram_labels ["<1s", "1-2s", "2-5s", "5-10s", "10-30s", "30-60s", ">60s"]

  # Bucket widths the volume chart may choose between, smallest first. Chosen
  # so a window of any supported length lands on roughly a dozen bars.
  @bucket_widths [
    60,
    300,
    900,
    1800,
    3600,
    7200,
    21_600,
    43_200,
    86_400,
    172_800,
    259_200,
    604_800
  ]

  # Error types that mean Lightning itself lost the run, whatever the run's
  # own state says. Written by `Lightning.Runs.mark_run_lost/1`.
  @platform_error_types ~w(LostAfterStart LostAfterClaim UnknownReason)

  # Error types raised by an adaptor talking to a system we do not control.
  @remote_error_types ~w(AdaptorError)

  # Run states that are failures of the platform rather than of the workflow.
  @platform_exit_reasons ~w(lost exception)

  @doc """
  Loads every panel on the health screen for one workflow and window.
  """
  @spec load(Workflow.t(), DateTime.t(), DateTime.t()) :: map()
  def load(%Workflow{} = workflow, from, to) do
    run_states = run_state_counts(workflow, from, to)
    signatures = step_signatures(workflow, from, to)
    runless = runless_signatures(workflow, from, to)

    %{
      outcomes: to_outcomes(run_states),
      failure_breakdown: to_failure_breakdown(run_states),
      steps_with_failures: to_steps_with_failures(signatures, runless),
      volume_over_time: volume_over_time(workflow, from, to),
      response_time: response_time(workflow, from, to),
      triage: to_triage(signatures, runless)
    }
  end

  @doc """
  The shape `load/3` returns, with everything zeroed.

  Lets a caller render the screen before it has data — on a LiveView's dead
  render, say — without every panel needing a nil check.
  """
  @spec empty() :: map()
  def empty do
    %{
      outcomes: to_outcomes(%{}),
      failure_breakdown: to_failure_breakdown(%{}),
      steps_with_failures: to_steps_with_failures([], []),
      volume_over_time: %{bucket_seconds: hd(@bucket_widths), buckets: []},
      response_time: %{
        p50: nil,
        p95: nil,
        max: nil,
        sampled: 0,
        histogram: Enum.map(@histogram_labels, &%{label: &1, runs: 0})
      },
      triage: []
    }
  end

  @doc """
  Run counts split into success and failure.

  Runs still in flight are counted separately so they never distort the
  success rate — a run that has not finished is not yet a failure.
  """
  def outcomes(workflow, from, to) do
    workflow |> run_state_counts(from, to) |> to_outcomes()
  end

  @doc """
  Failed runs grouped by how they failed, most common first.
  """
  def failure_breakdown(workflow, from, to) do
    workflow |> run_state_counts(from, to) |> to_failure_breakdown()
  end

  @doc """
  Step failures grouped by the job they happened on.

  Runs that failed before any step ran cannot be attributed to a job. They are
  returned as a row with `attributed: false` rather than being silently
  dropped, because on a broken workflow they are often the largest group.

  `total` counts the rows shown, so a run that failed on two steps contributes
  twice — this counts failing steps, not failing runs.
  """
  def steps_with_failures(workflow, from, to) do
    to_steps_with_failures(
      step_signatures(workflow, from, to),
      runless_signatures(workflow, from, to)
    )
  end

  @doc """
  Failures grouped by the closest thing to an error signature we can compute.

  A real signature needs the error message, which is not stored. Each group
  therefore carries `message: nil` and the caller is expected to show that the
  message is missing rather than invent one.
  """
  def triage(workflow, from, to) do
    to_triage(
      step_signatures(workflow, from, to),
      runless_signatures(workflow, from, to)
    )
  end

  @doc """
  Run counts bucketed over the window, split into total and failed.

  The bucket size is derived from the window so the chart always lands on
  roughly a dozen bars, and empty buckets are filled in — a gap in the data
  should read as a gap, not as a missing bar.
  """
  def volume_over_time(workflow, from, to) do
    seconds = bucket_seconds(from, to)
    failure_states = Run.failure_states()

    # The bucket expression lives in a subquery so Postgres can group by a
    # plain column. Repeating the fragment in both SELECT and GROUP BY gives
    # each copy a different parameter number, which Postgres refuses to match.
    bucketed =
      workflow
      |> runs_in_window(from, to)
      |> select([r], %{
        bucket:
          fragment(
            "(floor(extract(epoch from ?) / ?))::bigint",
            r.inserted_at,
            ^seconds
          ),
        state: r.state
      })

    counted =
      from(b in subquery(bucketed),
        group_by: b.bucket,
        select: %{
          bucket: b.bucket,
          runs: count(),
          failed: filter(count(), b.state in ^failure_states)
        }
      )
      |> Repo.all()
      |> Map.new(&{&1.bucket, &1})

    buckets =
      from
      |> bucket_starts(to, seconds)
      |> Enum.map(fn started_at ->
        index = started_at |> DateTime.to_unix() |> div(seconds)
        row = Map.get(counted, index, %{runs: 0, failed: 0})

        %{started_at: started_at, runs: row.runs, failed: row.failed}
      end)

    %{bucket_seconds: seconds, buckets: buckets}
  end

  @doc """
  Run duration percentiles and a histogram of durations.

  Only finished runs are considered — an in-flight run has no duration. The
  percentiles and the histogram come from one pass over the durations, since
  scanning them twice for numbers shown side by side is wasted work.
  """
  def response_time(workflow, from, to) do
    durations = duration_subquery(workflow, from, to)

    row =
      from(d in subquery(durations),
        select: %{
          p50:
            fragment("percentile_cont(0.5) within group (order by ?)", d.seconds),
          p95:
            fragment(
              "percentile_cont(0.95) within group (order by ?)",
              d.seconds
            ),
          max: max(d.seconds),
          sampled: count(),
          under_1s: filter(count(), d.seconds < 1.0),
          under_2s: filter(count(), d.seconds >= 1.0 and d.seconds < 2.0),
          under_5s: filter(count(), d.seconds >= 2.0 and d.seconds < 5.0),
          under_10s: filter(count(), d.seconds >= 5.0 and d.seconds < 10.0),
          under_30s: filter(count(), d.seconds >= 10.0 and d.seconds < 30.0),
          under_60s: filter(count(), d.seconds >= 30.0 and d.seconds < 60.0),
          over_60s: filter(count(), d.seconds >= 60.0)
        }
      )
      |> Repo.one()

    counts = [
      row.under_1s,
      row.under_2s,
      row.under_5s,
      row.under_10s,
      row.under_30s,
      row.under_60s,
      row.over_60s
    ]

    %{
      p50: round_seconds(row.p50),
      p95: round_seconds(row.p95),
      max: round_seconds(row.max),
      sampled: row.sampled,
      histogram:
        Enum.zip_with(@histogram_labels, counts, &%{label: &1, runs: &2})
    }
  end

  @doc """
  Classifies a failure by who would have to fix it.

  A heuristic over `exit_reason` and `error_type` — the only failure columns we
  store. It reads the exit reason first, because a killed or lost run is the
  platform's doing whatever raised it, and falls back to the error type for
  the cases that only it can distinguish. Good enough to sort a triage list,
  not good enough to act on automatically.
  """
  def blame(exit_reason, error_type)

  def blame(reason, _type) when reason in @platform_exit_reasons, do: :platform
  def blame(_reason, type) when type in @platform_error_types, do: :platform
  def blame("kill", _type), do: :limit
  def blame(_reason, type) when type in @remote_error_types, do: :remote
  def blame(_reason, _type), do: :user

  defp to_outcomes(counts) do
    pending =
      Run.active_states() |> Enum.map(&Map.get(counts, &1, 0)) |> Enum.sum()

    success = Map.get(counts, :success, 0)

    failed =
      Run.failure_states() |> Enum.map(&Map.get(counts, &1, 0)) |> Enum.sum()

    finished = success + failed

    %{
      total: finished + pending,
      pending: pending,
      success: success,
      failed: failed,
      success_rate: percentage(success, finished),
      failure_rate: percentage(failed, finished)
    }
  end

  defp to_failure_breakdown(counts) do
    reasons =
      counts
      |> Map.take(Run.failure_states())
      |> Enum.reject(fn {_state, count} -> count == 0 end)
      |> Enum.sort_by(&elem(&1, 1), :desc)

    total = reasons |> Enum.map(&elem(&1, 1)) |> Enum.sum()

    %{
      total: total,
      reasons:
        Enum.map(reasons, fn {state, count} ->
          %{state: state, count: count, percentage: percentage(count, total)}
        end)
    }
  end

  # Both panels below are roll-ups of the same two signature lists, so they are
  # derived in memory rather than re-queried.
  defp to_steps_with_failures(signatures, runless) do
    by_job =
      signatures
      |> Enum.group_by(& &1.job)
      |> Enum.map(fn {job, rows} ->
        %{job: job, count: sum_runs(rows), attributed: true}
      end)

    unattributed = sum_runs(runless)

    rows =
      if unattributed > 0 do
        [%{job: nil, count: unattributed, attributed: false} | by_job]
      else
        by_job
      end

    %{
      total: rows |> Enum.map(& &1.count) |> Enum.sum(),
      unattributed: unattributed,
      steps: Enum.sort_by(rows, & &1.count, :desc)
    }
  end

  defp to_triage(signatures, runless) do
    Enum.sort_by(signatures ++ runless, & &1.runs, :desc)
  end

  defp sum_runs(rows), do: rows |> Enum.map(& &1.runs) |> Enum.sum()

  defp run_state_counts(%Workflow{} = workflow, from, to) do
    workflow
    |> runs_in_window(from, to)
    |> group_by([r], r.state)
    |> select([r], {r.state, count(r.id)})
    |> Repo.all()
    |> Map.new()
  end

  # Failures that reached a step, grouped by that step and how it failed.
  # `job` is nil when the job row has since been deleted; the caller supplies
  # the wording for that case.
  defp step_signatures(%Workflow{} = workflow, from, to) do
    workflow
    |> failed_steps_in_window(from, to)
    |> join(:left, [s], j in assoc(s, :job))
    |> group_by([s, _rs, _r, _wo, j], [
      s.exit_reason,
      s.error_type,
      j.id,
      j.name,
      j.adaptor
    ])
    |> select([s, _rs, _r, _wo, j], %{
      exit_reason: s.exit_reason,
      error_type: s.error_type,
      job: j.name,
      adaptor: j.adaptor,
      runs: count(s.id, :distinct)
    })
    |> Repo.all()
    |> Enum.map(&Map.merge(&1, signature_extras(&1)))
  end

  # Failures that never reached a step — a compile error, say — grouped by the
  # run's own state and error type. Without this they would be missing from
  # triage entirely, even though they can be the largest group on a workflow
  # that is failing to start at all.
  defp runless_signatures(%Workflow{} = workflow, from, to) do
    failure_states = Run.failure_states()

    failing_step =
      from(rs in RunStep,
        join: s in Step,
        on: s.id == rs.step_id,
        where: rs.run_id == parent_as(:run).id,
        where: not is_nil(s.exit_reason) and s.exit_reason != "success",
        select: 1
      )

    workflow
    |> runs_in_window(from, to)
    |> from(as: :run)
    |> where([r], r.state in ^failure_states)
    |> where([r], not exists(failing_step))
    |> group_by([r], [r.state, r.error_type])
    |> select([r], %{state: r.state, error_type: r.error_type, runs: count(r.id)})
    |> Repo.all()
    |> Enum.map(fn row ->
      row
      |> Map.delete(:state)
      |> Map.merge(%{
        exit_reason: exit_reason_for(row.state),
        job: nil,
        adaptor: nil,
        runs: row.runs
      })
      |> then(&Map.merge(&1, signature_extras(&1)))
    end)
  end

  defp signature_extras(%{exit_reason: exit_reason, error_type: error_type}) do
    %{blame: blame(exit_reason, error_type), message: nil}
  end

  # Runs record a state; steps record the matching exit reason. Triage shows
  # both kinds of failure in one list, so run states are named the step way.
  defp exit_reason_for(:failed), do: "fail"
  defp exit_reason_for(:crashed), do: "crash"
  defp exit_reason_for(:killed), do: "kill"
  defp exit_reason_for(:cancelled), do: "cancel"
  defp exit_reason_for(:exception), do: "exception"
  defp exit_reason_for(:lost), do: "lost"

  defp runs_in_window(%Workflow{id: workflow_id}, from, to) do
    from(r in Run,
      join: wo in WorkOrder,
      on: wo.id == r.work_order_id,
      where: wo.workflow_id == ^workflow_id,
      where: r.inserted_at >= ^from and r.inserted_at < ^to
    )
  end

  defp failed_steps_in_window(%Workflow{id: workflow_id}, from, to) do
    from(s in Step,
      join: rs in RunStep,
      on: rs.step_id == s.id,
      join: r in Run,
      on: r.id == rs.run_id,
      join: wo in WorkOrder,
      on: wo.id == r.work_order_id,
      where: wo.workflow_id == ^workflow_id,
      where: r.inserted_at >= ^from and r.inserted_at < ^to,
      where: not is_nil(s.exit_reason) and s.exit_reason != "success"
    )
  end

  defp duration_subquery(workflow, from, to) do
    workflow
    |> runs_in_window(from, to)
    |> where([r], not is_nil(r.started_at) and not is_nil(r.finished_at))
    |> select([r], %{
      seconds:
        fragment("extract(epoch from (? - ?))", r.finished_at, r.started_at)
    })
  end

  # Aim for 12-ish buckets, snapped to a width a person would recognise.
  defp bucket_seconds(from, to) do
    target = max(div(DateTime.diff(to, from, :second), 12), 1)

    Enum.find(@bucket_widths, List.last(@bucket_widths), &(&1 >= target))
  end

  defp bucket_starts(from, to, seconds) do
    first = from |> DateTime.to_unix() |> div(seconds) |> Kernel.*(seconds)
    last = to |> DateTime.to_unix() |> div(seconds) |> Kernel.*(seconds)

    first
    |> Stream.iterate(&(&1 + seconds))
    |> Stream.take_while(&(&1 <= last))
    |> Enum.map(&DateTime.from_unix!/1)
  end

  defp percentage(_count, 0), do: 0.0
  defp percentage(count, total), do: Float.round(count * 100 / total, 1)

  defp round_seconds(nil), do: nil
  defp round_seconds(seconds), do: seconds |> to_float() |> Float.round(2)

  defp to_float(%Decimal{} = decimal), do: Decimal.to_float(decimal)
  defp to_float(number) when is_float(number), do: number
  defp to_float(number) when is_integer(number), do: number / 1
end
