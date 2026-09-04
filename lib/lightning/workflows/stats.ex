defmodule Lightning.Workflows.Stats do
  @moduledoc """
  Stats for a single workflow or a whole project, shaped for the health pages.

  One public function per chart, each returning only what that chart draws, so a
  cheap chart renders without waiting on an expensive one.

  A failed work order is attributed to every failing step of its latest run, so
  a run that broke in two branches is a row in both. Each row counts work
  orders, not steps, which means the rows can sum past the failure total the
  donuts draw.

  Deliberately independent of `Lightning.DashboardStats`, which serves the
  workflow list view: it batches across many workflows to avoid an N+1 while
  this page queries one, and `count_workorders/1` collapses every failure state
  into a single `:failed` bucket — the granularity both donuts need apart.
  """
  import Ecto.Query

  alias Lightning.Invocation.Step
  alias Lightning.Projects.Project
  alias Lightning.Repo
  alias Lightning.Run
  alias Lightning.RunStep
  alias Lightning.Workflows.Query
  alias Lightning.Workflows.Snapshot
  alias Lightning.Workflows.Workflow
  alias Lightning.WorkOrder

  @default_days_back 30

  # Short enough that the page stays honest during an incident, long enough to
  # collapse a burst of viewers into one query.
  @ttl :timer.seconds(30)

  @final_states WorkOrder.final_states()
  @zero_counts Map.new(@final_states, &{&1, 0})

  # `:cancelled` is final but not a failure — someone stopped it on purpose. Own
  # outcome, not the red wedge, which is why this narrows the schema's list
  # rather than changing it.
  @failure_states WorkOrder.failure_states() -- [:cancelled]

  # The signature grammar is written in the worker's words, so a
  # run-level failure has to be mapped back out of its state.
  @state_reasons Run.state_reasons()

  @doc """
  Work order counts by final state over the last `days_back` days, for a
  single workflow or aggregated across every non-deleted workflow in a
  project.
  """
  def outcomes(scope, days_back \\ @default_days_back)

  def outcomes(%Workflow{id: workflow_id}, days_back) when days_back > 0 do
    cached({:outcomes, :workflow, workflow_id, days_back}, fn ->
      build_outcomes(dynamic([wo], wo.workflow_id == ^workflow_id), days_back)
    end)
  end

  def outcomes(%Project{id: project_id} = project, days_back)
      when days_back > 0 do
    cached({:outcomes, :project, project_id, days_back}, fn ->
      # `exclude(:order_by)` because `workflows_for/1` sorts, which is
      # meaningless inside an `IN` subquery.
      workflow_ids =
        project
        |> Query.workflows_for()
        |> exclude(:order_by)
        |> select([w], w.id)

      build_outcomes(
        dynamic([wo], wo.workflow_id in subquery(workflow_ids)),
        days_back
      )
    end)
  end

  defp build_outcomes(scope_filter, days_back) do
    to = DateTime.utc_now()
    since = DateTime.add(to, -days_back, :day)

    %{
      window: %{from: since, to: to},
      counts: count_work_orders(scope_filter, since)
    }
  end

  # Every final state is reported and zero-filled, so both donuts read the same
  # aggregate two ways without a second round trip. The window is anchored on
  # `last_activity`, not `inserted_at`: an old work order retried today is
  # counted as the work it currently is.
  defp count_work_orders(scope_filter, since) do
    from(wo in WorkOrder,
      where: ^scope_filter,
      where: wo.last_activity > ^since and wo.state in ^@final_states,
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
  def failure_signatures(
        %Workflow{id: workflow_id},
        days_back \\ @default_days_back
      )
      when days_back > 0 do
    cached({:failures, workflow_id, days_back}, fn ->
      to = DateTime.utc_now()
      since = DateTime.add(to, -days_back, :day)

      %{
        window: %{from: since, to: to},
        signatures: group_by_signature(workflow_id, since)
      }
    end)
  end

  @doc """
  Drops every cached slice and window for a workflow, so the next read
  recomputes.

  Called when one of its work orders settles. Without it, the refresh the
  health page just triggered would be answered out of the value cached before
  the change — the page would make a request and draw the same numbers.
  """
  def invalidate(workflow_id) do
    # Every key is `{slice, workflow_id, days_back}`, so element 2 is the
    # workflow. The filter runs in ETS: only this workflow's keys cross back
    # into Elixir, however many other workflows are cached alongside it.
    query =
      Cachex.Query.build(
        where: {:==, {:element, 2, :key}, workflow_id},
        output: :key
      )

    :workflow_stats
    |> Cachex.stream!(query)
    |> Enum.each(&Cachex.del(:workflow_stats, &1))
  end

  # Cached whole, `window` included — that is what stops the window rolling per
  # request. `Cachex.fetch/4` dedupes concurrent misses on the same key.
  defp cached(key, fun) do
    case Cachex.fetch(:workflow_stats, key, fn ->
           {:commit, fun.(), expire: @ttl}
         end) do
      {tag, value} when tag in [:ok, :commit] -> value
    end
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
        where:
          rs.run_id == parent_as(:latest_run).run_id and
            s.exit_reason != "success",
        select: %{
          exit_reason: s.exit_reason,
          error_type: s.error_type,
          snapshot_id: s.snapshot_id,
          job_id: s.job_id
        }
      )

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
      on: r.work_order_id == wo.id,
      where:
        wo.workflow_id == ^workflow_id and wo.last_activity > ^since and
          wo.state in ^@failure_states,
      distinct: wo.id,
      order_by: [asc: wo.id, desc_nulls_last: r.finished_at, desc: r.id],
      select: %{
        work_order_id: wo.id,
        work_order_state: wo.state,
        run_id: r.id,
        run_state: r.state,
        run_error_type: r.error_type
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
