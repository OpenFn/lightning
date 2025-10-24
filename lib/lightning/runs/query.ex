defmodule Lightning.Runs.Query do
  @moduledoc """
  Query functions for working with Runs
  """
  import Ecto.Query

  alias Lightning.Invocation.Step
  alias Lightning.Run

  require Lightning.Run

  @doc """
  Return all runs that have been claimed by a worker before the earliest
  acceptable start time (determined by the run options and grace period) but are
  still incomplete.

  This indicates that we may have lost contact with the worker
  that was responsible for executing the run.
  """
  @spec lost :: Ecto.Queryable.t()
  def lost do
    now = Lightning.current_time()

    grace_period_ms = Lightning.Config.grace_period() * 1000

    # TODO: Remove after live deployment rollouts are done. ====================
    fallback_max = Lightning.Config.default_max_run_duration()

    fallback_oldest_claim =
      now
      |> DateTime.add(-fallback_max, :second)
      |> DateTime.add(-grace_period_ms, :millisecond)

    # ==========================================================================

    final_states = Run.final_states()

    from(r in Run,
      where: is_nil(r.finished_at),
      where: r.state not in ^final_states,
      where:
        fragment(
          "COALESCE(?, ?) + ((? ->> 'run_timeout_ms')::int + ?) * '1 millisecond'::interval < ?",
          r.started_at,
          r.claimed_at,
          r.options,
          ^grace_period_ms,
          ^now
        ) or
          (is_nil(r.options) and
             fragment(
               "COALESCE(?, ?) < ?",
               r.started_at,
               r.claimed_at,
               ^fallback_oldest_claim
             )),
      lock: "FOR UPDATE SKIP LOCKED"
    )
  end

  @spec lost_steps() :: Ecto.Queryable.t()
  def lost_steps do
    final_states = Run.final_states()
    grace_period_seconds = Lightning.Config.grace_period()

    grace_cutoff =
      Lightning.current_time() |> DateTime.add(-grace_period_seconds, :second)

    from s in Step,
      join: r in assoc(s, :runs),
      on: r.state in ^final_states,
      where: is_nil(s.exit_reason) and is_nil(s.finished_at),
      where: r.finished_at < ^grace_cutoff
  end

  @doc """
  Applies concurrency window functions to workflow-limited run data.

  This function takes the output from `workflow_limited_runs/1` and applies
  SQL window functions to calculate row numbers within concurrency partitions.

  ## Partitioning Logic

  Runs are partitioned (grouped) by workflow or project for row numbering.
  Workflow concurrency takes precedence over project concurrency when both are set.
  Within each partition, runs are ordered by priority and insertion time.

  ## Return Fields

  Returns a query that selects:
  - `id` - the run ID
  - `state` - the current state of the run
  - `row_number` - sequential number within the concurrency partition
  - `project_id` - the project ID
  - `concurrency` - the maximum concurrent runs allowed (workflow or project level)
  - `inserted_at` - when the run was created
  - `priority` - the run's priority level

  The `row_number` field is used downstream to enforce concurrency limits by
  comparing it against the `concurrency` value.
  """
  @spec in_progress_window() :: Ecto.Queryable.t()
  def in_progress_window do
    # Use configurable per-workflow limit for the optimization
    per_workflow_limit = Lightning.Config.per_workflow_claim_limit()

    from(wlr in subquery(workflow_limited_runs(per_workflow_limit)))
    |> windows([wlr],
      partition_window: [
        partition_by: wlr.partition_key,
        order_by: [asc: wlr.inserted_at]
      ]
    )
    |> select([wlr], %{
      id: wlr.id,
      state: wlr.state,
      row_number: row_number() |> over(:partition_window),
      project_id: wlr.project_id,
      concurrency: wlr.concurrency,
      inserted_at: wlr.inserted_at,
      priority: wlr.priority
    })
  end

  @doc """
  Query to return runs that are eligible for claiming.

  This is the main function used by other parts of the system to get runs ready
  for execution. It implements a performance-optimized approach to run claiming
  that ensures fairness across workflows while respecting concurrency limits.

  ## Algorithm

  1. **Workflow Limiting**: Limits the number of runs per workflow to prevent any
     single workflow from dominating the processing queue
  2. **Window Processing**: Applies row numbering within concurrency partitions
     (workflow or project level) on the workflow-limited dataset
  3. **Concurrency Enforcement**: Uses the row numbers to enforce concurrency
     limits during run claiming
  4. **Availability Filtering**: Filters for available runs within concurrency limits
  5. **Priority Ordering**: Orders results by priority and insertion time

  ## Implementation

  The function uses a multi-step approach for performance optimization:

  1. **Pre-filtering**: Uses `workflow_limited_runs/1` to limit runs per workflow
     (configurable via `:per_workflow_claim_limit`) preventing any single workflow
     from dominating the claim queue while ensuring fairness
  2. **Window Functions**: Applies `in_progress_window/0` to calculate row numbers
     within concurrency partitions on the smaller, pre-filtered dataset
  3. **Final Filtering**: Selects only available runs that fall within their
     concurrency limits (where `row_number <= concurrency`)

  ## Concurrency Logic

  Workflow concurrency takes precedence over project concurrency when both are set.
  This ensures that workflow-level limits are respected first, with project-level
  limits serving as a fallback.

  ## Performance Notes

  The dataset is first limited per workflow (default: 50 runs) to manage the size
  of data processed by expensive window functions, significantly improving query
  performance on large datasets.

  > ### Note {: .info}
  > The default `:per_workflow_claim_limit` is 50.
  > This can be configured via the `PER_WORKFLOW_CLAIM_LIMIT` environment variable.
  > The value must be larger than the max concurrency of any individual workflow.

  Returns runs ordered by priority and insertion time that can be safely claimed
  without violating concurrency limits.
  """
  @spec eligible_for_claim() :: Ecto.Queryable.t()
  def eligible_for_claim do
    Run
    |> with_cte("subset", as: ^available_within_concurrency_limits())
    |> join(:inner, [r], subset in fragment(~s("subset")), on: r.id == subset.id)
    |> order_by([r], asc: r.priority, asc: r.inserted_at)
  end

  @doc """
  Query to return available runs that respect concurrency limits.

  This function combines run state filtering with concurrency enforcement by:
  1. Joining runs with their windowed concurrency data from `in_progress_window/0`
  2. Filtering for runs in `:available` state only
  3. Ensuring runs don't exceed their concurrency limits (workflow or project level)
  4. Ordering by priority and insertion time for fair processing

  ## Concurrency Logic

  A run is included if:
  - It's in `:available` state (not claimed, started, or finished)
  - Either no concurrency limit is set (`concurrency` is nil) OR
  - The run's position within its concurrency group (`row_number`) is within the limit

  Returns run IDs that can be safely claimed without violating concurrency constraints.
  """
  @spec available_within_concurrency_limits() :: Ecto.Queryable.t()
  def available_within_concurrency_limits(
        in_progress_window_query \\ in_progress_window()
      ) do
    from(r in Run)
    |> join(:inner, [r], ipw in subquery(in_progress_window_query),
      on: r.id == ipw.id,
      as: :in_progress_window
    )
    |> where(
      [r, ipw],
      r.state == :available and
        (is_nil(ipw.concurrency) or ipw.row_number <= ipw.concurrency)
    )
    |> select([r, ipw], %{id: r.id, project_id: ipw.project_id})
    |> order_by([r, ipw], asc: r.priority, asc: r.inserted_at)
  end

  @doc """
  Query to return workflow-limited runs with priority-based ranking.

  This function creates a dataset where each workflow contributes at most
  `per_workflow_limit` runs, ranked by priority and insertion time. This prevents
  any single workflow from dominating the claim queue while ensuring fairness.

  Returns runs with workflow ranking information needed for further processing.
  """
  @spec workflow_limited_runs(pos_integer()) :: Ecto.Queryable.t()
  def workflow_limited_runs(per_workflow_limit \\ 50) do
    # Step 1: Rank runs within each workflow by priority and insertion time
    ranked_runs_query =
      from(r in Run,
        where: r.state in [:available, :claimed, :started],
        join: wo in assoc(r, :work_order),
        join: w in assoc(wo, :workflow),
        join: p in assoc(w, :project)
      )
      |> windows([r, _wo, w, _p],
        workflow_window: [
          partition_by: w.id,
          order_by: [asc: r.priority, asc: r.inserted_at]
        ]
      )
      |> select([r, _wo, w, p], %{
        id: r.id,
        state: r.state,
        project_id: w.project_id,
        concurrency: coalesce(w.concurrency, p.concurrency),
        inserted_at: r.inserted_at,
        priority: r.priority,
        workflow_id: w.id,
        project_id_alt: p.id,
        partition_key:
          fragment(
            "CASE WHEN ? IS NOT NULL THEN ? ELSE ? END",
            w.concurrency,
            w.id,
            p.id
          ),
        workflow_rn: row_number() |> over(:workflow_window)
      })

    # Step 2: Filter to only keep top N runs per workflow
    from(wlr in subquery(ranked_runs_query),
      where: wlr.workflow_rn <= ^per_workflow_limit,
      select: wlr
    )
  end
end
