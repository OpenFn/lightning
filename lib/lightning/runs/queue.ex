defmodule Lightning.Runs.Queue do
  @moduledoc """
  Allows adding, removing or claiming work to be executed by the Runtime.
  """
  import Ecto.Query

  alias Lightning.Repo
  alias Lightning.Runs

  @spec claim(
          non_neg_integer(),
          Ecto.Query.t(),
          String.t() | nil,
          [String.t()]
        ) ::
          {:ok, [Lightning.Run.t()]}
          | {:error, Ecto.Changeset.t(Lightning.Run.t())}
  def claim(demand, base_query, worker_name \\ nil, queues \\ ["manual", "*"]) do
    log = Lightning.Config.log_queue_queries()

    Ecto.Multi.new()
    |> Ecto.Multi.run(:configure_session, fn repo, _changes ->
      work_mem = Lightning.Config.claim_work_mem()

      with {:ok, _} <-
             repo.query(
               "SET LOCAL plan_cache_mode = force_custom_plan",
               [],
               log: log
             ),
           {:ok, _} <- maybe_set_work_mem(repo, work_mem, log) do
        {:ok, :session_configured}
      end
    end)
    |> Ecto.Multi.run(:claim_runs, fn _repo, _changes ->
      subset_query =
        base_query
        |> apply_queue_and_ordering(queues)
        |> select([:id])
        |> where([r], r.state == :available)
        |> limit(^demand)
        |> lock("FOR UPDATE SKIP LOCKED")

      # The Postgres planner may choose to generate a plan that executes a nested
      # loop over the LIMITing subquery, causing more UPDATEs than LIMIT.
      # That could cause unexpected updates, including rows that we would
      # assume would be excluded in the base query in some cases.
      # The solution is to use a CTE as an "optimization fence" that forces
      # Postgres _not_ to optimize the query.
      #
      # The odd "subset" fragment is required to prevent Ecto from applying the
      # prefix to the name of the CTE, e.g. "public"."subset".
      query =
        Lightning.Run
        |> with_cte("subset", as: ^subset_query)
        |> join(:inner, [a], x in fragment(~s("subset")), on: true)
        |> where([a, x], a.id == x.id)
        |> select([a, _], a)

      Runs.update_runs(
        query,
        set: [
          state: :claimed,
          claimed_at: DateTime.utc_now(),
          worker_name: worker_name
        ]
      )
    end)
    |> Repo.transaction(log: log)
    |> case do
      {:ok, %{claim_runs: %{runs: {_count, runs}}}} ->
        {:ok, runs}

      {:error, _op, changeset, _changes} ->
        {:error, changeset}
    end
  end

  # Rebuilds ordering as: queue_preference (if any), then the base query's
  # original ordering.  This preserves caller-supplied ordering (e.g. the
  # project_id column used by Thunderbolt's round-robin scheduler) while
  # letting queue preference take highest precedence.
  defp apply_queue_and_ordering(query, queues) do
    saved_order_bys = query.order_bys

    query
    |> exclude(:order_by)
    |> apply_queue_clause(queues)
    |> then(fn q -> %{q | order_bys: q.order_bys ++ saved_order_bys} end)
  end

  defp apply_queue_clause(query, queues) do
    if "*" in queues do
      # Preference mode: order named queues by array position,
      # wildcard fills the gap for all other queues
      named =
        Enum.map(queues, fn
          "*" -> "__wildcard__"
          q -> q
        end)

      # 1-based index for PostgreSQL
      wildcard_pos = Enum.find_index(queues, &(&1 == "*")) + 1

      if Enum.all?(queues, &(&1 == "*")) do
        # ["*"] alone means no preference ordering
        query
      else
        order_by(
          query,
          [r],
          asc:
            fragment(
              "COALESCE(array_position(?, ?), ?)",
              type(^named, {:array, :string}),
              r.queue,
              ^wildcard_pos
            )
        )
      end
    else
      # Filter mode: only named queues
      where(query, [r], r.queue in ^queues)
    end
  end

  defp maybe_set_work_mem(_repo, nil, _log), do: {:ok, :skipped}

  defp maybe_set_work_mem(repo, work_mem, log),
    do:
      repo.query("SELECT set_config('work_mem', $1, true)", [work_mem], log: log)
end
