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
          "? + ((? ->> 'run_timeout_ms')::int + ?) * '1 millisecond'::interval < ?",
          r.claimed_at,
          r.options,
          ^grace_period_ms,
          ^now
        ) or (is_nil(r.options) and r.claimed_at < ^fallback_oldest_claim)
    )
  end

  @spec lost_steps() :: Ecto.Queryable.t()
  def lost_steps do
    final_states = Run.final_states()

    from s in Step,
      join: r in assoc(s, :runs),
      on: r.state in ^final_states,
      where: is_nil(s.exit_reason) and is_nil(s.finished_at)
  end

  @doc """
  Query to return a list of runs that are either in progress (started or claimed)
  or available.

  It returns a row_number (sequential number) for each run partitioned (grouped by) workflow or project.
  If workflow concurrency is set it takes precedence over project concurrency.

  Note that this query does NOT consider the smaller concurrency once it's not enough to assure that
  project concurrency is always respected (e.g when 2 workflows of same project have concurrency 3 on a project
  with concurrency 5, 3 is less than 5 but still project concurrency wouldn't be respected).
  Instead the LV makes sure that a workflow concurrency sum does not exceed the project concurrency.

  The select clause includes:
  - `id`, the id of the run
  - `state`, the state of the run
  - `row_number`, the number of the row in the window, per workflow or per project
  - `concurrency`, the maximum number of runs that can be claimed for the workflow
  """
  @spec in_progress_window() :: Ecto.Queryable.t()
  def in_progress_window do
    from(r in Run,
      where: r.state in [:available, :claimed, :started],
      join: wo in assoc(r, :work_order),
      join: w in assoc(wo, :workflow),
      join: p in assoc(w, :project)
    )
    |> select([r, _wo, w, p], %{
      id: r.id,
      state: r.state,
      # need to check what performance implications are of using row_number
      # does the subsequent query's limit clause get applied to the row_number
      # calculated here?
      w_row_number:
        row_number() |> over(partition_by: w.id, order_by: r.inserted_at),
      p_row_number:
        row_number() |> over(partition_by: p.id, order_by: r.inserted_at),
      project_id: w.project_id,
      w_concurrency: coalesce(w.concurrency, p.concurrency),
      p_concurrency: coalesce(p.concurrency, 100),
      inserted_at: r.inserted_at
    })
  end

  @doc """
  Query to return runs that are eligible for claiming.

  Uses `in_progress_window/0` and filters for runs that are either in the
  available state and have not reached the concurrency limit for their workflow.

  > ### Note {: .info}
  > This query does not currently take into account the priority of the run.
  > To allow for prioritization, the query should be updated to order by
  > priority.
  >
  > ```elixir
  > eligible_for_claim() |> prepend_order_by([:priority])
  > ```
  """
  @spec eligible_for_claim() :: Ecto.Queryable.t()
  def eligible_for_claim do
    Run
    |> with_cte("in_progress_window", as: ^in_progress_window())
    |> join(:inner, [r], ipw in fragment(~s("in_progress_window")),
      on: r.id == ipw.id,
      as: :in_progress_window
    )
    |> where(
      [r, ipw],
      r.state == :available and
        (is_nil(ipw.w_concurrency) or
           (ipw.w_row_number <= ipw.w_concurrency and
              ipw.p_row_number <= ipw.p_concurrency))
    )
    |> order_by([r], asc: r.inserted_at)
  end
end
