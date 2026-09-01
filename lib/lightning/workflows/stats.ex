defmodule Lightning.Workflows.Stats do
  @moduledoc """
  Stats for a single workflow, shaped for the workflow health page.

  One public function per chart, each returning only what that chart draws. The
  page requests them separately so a cheap chart renders without waiting on an
  expensive one — a single merged payload would make every chart pay for the
  slowest query.

  The page's unit is the run, not the work order. A retry is a second attempt
  with its own outcome, and the panels that attribute failures — the failure
  breakdown, and later the triage table — can only name a state that belongs to
  an attempt. Counting work orders here and runs there would put two different
  totals on the same screen.

  Deliberately independent of `Lightning.DashboardStats`, which serves the
  workflow list view. The two answer similar questions today, but the list view
  batches across many workflows to avoid an N+1 while this page queries one, and
  their windows will diverge as soon as this page grows a range picker. Sharing
  the module would make each page pay for the other's requirements.
  """
  import Ecto.Query

  alias Lightning.Invocation.Step
  alias Lightning.Repo
  alias Lightning.Run
  alias Lightning.RunStep
  alias Lightning.Workflows.Job
  alias Lightning.Workflows.Workflow
  alias Lightning.WorkOrder

  @default_days_back 30

  @final_states Run.final_states()
  @failure_states Run.failure_states()
  @zero_counts Map.new(@final_states, &{&1, 0})

  # The signature grammar (CON-31) is written in the worker's words, so a
  # run-level failure has to be mapped back out of its state.
  @state_reasons Run.state_reasons()

  @doc """
  Run counts by final state over the last `days_back` days.

  The window is echoed as bounds rather than a day count, so a range picker
  lands as a request param instead of a payload change.
  """
  def outcomes(%Workflow{id: workflow_id}, days_back \\ @default_days_back)
      when days_back > 0 do
    to = DateTime.utc_now()
    since = DateTime.add(to, -days_back, :day)

    %{
      window: %{from: since, to: to},
      counts: count_runs(workflow_id, since)
    }
  end

  # Every final state is reported and zero-filled, so the outcomes donut folds
  # them into success/failed and the failure breakdown slices the rest without a
  # second round trip — it is the same aggregate read two ways. Runs still in
  # flight are left out entirely; the page only draws finished outcomes.
  defp count_runs(workflow_id, since) do
    from(r in Run,
      join: wo in WorkOrder,
      on: wo.id == r.work_order_id,
      where:
        wo.workflow_id == ^workflow_id and r.inserted_at > ^since and
          r.state in ^@final_states,
      group_by: r.state,
      select: {r.state, count(r.id)}
    )
    |> Repo.all()
    |> Enum.into(@zero_counts)
  end

  @doc """
  Failed runs grouped by error signature over the last `days_back` days.

  The signature's parts are returned separately rather than as one string: the
  table styles each part differently, and the tip is looked up by `error_type`.
  Assembling it here would only force the client to take it apart again.

  Counts are runs, and every failed run lands in exactly one group, so these
  add up to the failure total the outcomes donut draws.
  """
  def failure_signatures(
        %Workflow{id: workflow_id},
        days_back \\ @default_days_back
      )
      when days_back > 0 do
    to = DateTime.utc_now()
    since = DateTime.add(to, -days_back, :day)

    %{
      window: %{from: since, to: to},
      signatures: group_by_signature(workflow_id, since)
    }
  end

  # A run can fail more than one step once `on_job_failure` edges are in play,
  # so one is picked — the earliest, which is what actually broke. Anything
  # else would let the rows sum past the number of failed runs.
  defp attributed_failures(workflow_id, since) do
    from(r in Run,
      join: wo in WorkOrder,
      on: wo.id == r.work_order_id,
      left_join: rs in RunStep,
      on: rs.run_id == r.id,
      left_join: s in Step,
      on: s.id == rs.step_id and s.exit_reason != "success",
      where:
        wo.workflow_id == ^workflow_id and r.inserted_at > ^since and
          r.state in ^@failure_states,
      distinct: r.id,
      # `s.id` breaks the tie so a failing step that never stamped `started_at`
      # still beats the null row a filtered-out successful step leaves behind —
      # otherwise the run reads as having reached no step at all.
      order_by: [asc: r.id, asc_nulls_last: s.started_at, asc_nulls_last: s.id],
      select: %{
        run_state: r.state,
        run_error_type: r.error_type,
        exit_reason: s.exit_reason,
        error_type: s.error_type,
        job_id: s.job_id
      }
    )
  end

  # The job is joined live, so a rename or an adaptor bump relabels history —
  # `workflow_snapshots.jobs` holds what the run actually saw. Reading the
  # snapshot means digging through JSONB per row, and the current name is what
  # someone acting on this table will go looking for.
  defp group_by_signature(workflow_id, since) do
    from(a in subquery(attributed_failures(workflow_id, since)),
      left_join: j in Job,
      on: j.id == a.job_id,
      group_by: [
        a.exit_reason,
        a.error_type,
        a.run_state,
        a.run_error_type,
        j.name,
        j.adaptor
      ],
      select: %{
        exit_reason: a.exit_reason,
        error_type: a.error_type,
        run_state: a.run_state,
        run_error_type: a.run_error_type,
        step_name: j.name,
        adaptor: j.adaptor,
        count: count()
      }
    )
    |> Repo.all()
    |> Enum.map(&to_signature/1)
    |> merge_counts()
  end

  # A step that finished carries its own reason and error type; one that never
  # reported — a lost or reaped run — carries only the reason, and the rest
  # comes off the run. `mark_steps_lost/1` is why: it stamps `exit_reason` and
  # leaves `error_type` alone.
  defp to_signature(row) do
    %{
      count: row.count,
      exit_reason: row.exit_reason || @state_reasons[row.run_state],
      error_type: row.error_type || row.run_error_type,
      step_name: row.step_name,
      adaptor: row.adaptor
    }
  end

  # Two groups can collapse into one signature — a crashed run and a failed run
  # whose steps both reported `fail`, say — so the fold happens after the
  # coalesce, not in the `group_by`.
  defp merge_counts(signatures) do
    signatures
    |> Enum.group_by(&Map.delete(&1, :count), & &1.count)
    |> Enum.map(fn {signature, counts} ->
      Map.put(signature, :count, Enum.sum(counts))
    end)
    |> Enum.sort_by(&{-&1.count, &1.step_name}, :asc)
  end
end
