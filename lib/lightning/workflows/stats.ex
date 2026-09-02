defmodule Lightning.Workflows.Stats do
  @moduledoc """
  Stats for a single workflow, shaped for the workflow health page.

  One public function per chart, each returning only what that chart draws, so a
  cheap chart renders without waiting on an expensive one.

  A failed work order is attributed to its latest run's earliest failing step,
  so the triage rows sum to exactly the failure total the donuts draw.

  Deliberately independent of `Lightning.DashboardStats`, which serves the
  workflow list view: it batches across many workflows to avoid an N+1 while
  this page queries one, and `count_workorders/1` collapses every failure state
  into a single `:failed` bucket — the granularity both donuts need apart.
  """
  import Ecto.Query

  alias Lightning.Invocation.Step
  alias Lightning.Repo
  alias Lightning.Run
  alias Lightning.RunStep
  alias Lightning.Workflows.Snapshot
  alias Lightning.Workflows.Workflow
  alias Lightning.WorkOrder

  @default_days_back 30

  @final_states WorkOrder.final_states()
  @zero_counts Map.new(@final_states, &{&1, 0})

  # `:cancelled` is final but not a failure — someone stopped it on purpose. Own
  # outcome, not the red wedge, which is why this narrows the schema's list
  # rather than changing it.
  @failure_states WorkOrder.failure_states() -- [:cancelled]

  # The signature grammar (CON-31) is written in the worker's words, so a
  # run-level failure has to be mapped back out of its state.
  @state_reasons Run.state_reasons()

  @doc """
  Work order counts by final state over the last `days_back` days.
  """
  def outcomes(%Workflow{id: workflow_id}, days_back \\ @default_days_back)
      when days_back > 0 do
    to = DateTime.utc_now()
    since = DateTime.add(to, -days_back, :day)

    %{
      window: %{from: since, to: to},
      counts: count_work_orders(workflow_id, since)
    }
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

  Every failed work order lands in exactly one group, so these add up to the
  failure total the outcomes donut draws.
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

  # One row per failed work order — the latest run, which is the one whose
  # completion set the work order's state, and the earliest step that failed
  # within it. Earliest matters when an `:on_job_failure` edge routes to a job
  # that fails too: the second failure is fallout, not the cause.
  defp attributed_failures(workflow_id, since) do
    from(wo in WorkOrder,
      # left_join, not join: a rejected work order has no run and still counts.
      left_join: r in Run,
      on: r.work_order_id == wo.id,
      left_join: rs in RunStep,
      on: rs.run_id == r.id,
      left_join: s in Step,
      on: s.id == rs.step_id and s.exit_reason != "success",
      where:
        wo.workflow_id == ^workflow_id and wo.last_activity > ^since and
          wo.state in ^@failure_states,
      distinct: wo.id,
      # `s.id` breaks the tie so a failing step that never stamped `started_at`
      # still beats the null row a filtered-out successful step leaves behind —
      # otherwise the run reads as having reached no step at all.
      order_by: [
        asc: wo.id,
        desc_nulls_last: r.finished_at,
        desc: r.id,
        asc_nulls_last: s.started_at,
        asc_nulls_last: s.id
      ],
      select: %{
        work_order_state: wo.state,
        run_state: r.state,
        run_error_type: r.error_type,
        exit_reason: s.exit_reason,
        error_type: s.error_type,
        snapshot_id: s.snapshot_id,
        job_id: s.job_id
      }
    )
  end

  # The job's name and adaptor come off the run's own snapshot, not the live
  # `jobs` table: a rename or an adaptor bump must not relabel history, and a
  # job since deleted still has to be nameable. Resolving after the group keeps
  # the jsonb unnest down to the few snapshots that actually failed in the
  # window — joining it in would unnest every snapshot the workflow ever had.
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
          count: count()
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
  # different name in every snapshot that renamed it. Only `name` and `adaptor`
  # are read out, so the job bodies alongside them never cross the wire.
  defp snapshot_jobs([]), do: %{}

  defp snapshot_jobs(snapshot_ids) do
    from(s in Snapshot,
      where: s.id in ^snapshot_ids,
      cross_lateral_join: j in fragment("jsonb_array_elements(?)", s.jobs),
      select:
        {{s.id, fragment("? ->> ?", j, "id")},
         {fragment("? ->> ?", j, "name"), fragment("? ->> ?", j, "adaptor")}}
    )
    |> Repo.all()
    |> Map.new()
  end

  # A rejected work order never got a run, so there is no signature to read.
  # `:rejected` has one origin — the run limit refusing a webhook payload — so
  # the label names it outright.
  defp to_signature(%{work_order_state: :rejected} = row, _jobs) do
    %{
      count: row.count,
      exit_reason: "rejected",
      error_type: "RunLimitExceeded",
      step_name: nil,
      adaptor: nil
    }
  end

  # A step that finished carries its own reason and error type; one that never
  # reported — a lost or reaped run — carries only the reason, and the rest
  # comes off the run. `mark_steps_lost/1` is why: it stamps `exit_reason` and
  # leaves `error_type` alone.
  defp to_signature(row, jobs) do
    {step_name, adaptor} =
      Map.get(jobs, {row.snapshot_id, row.job_id}, {nil, nil})

    %{
      count: row.count,
      exit_reason: row.exit_reason || @state_reasons[row.run_state],
      error_type: row.error_type || row.run_error_type,
      step_name: step_name,
      adaptor: adaptor
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
