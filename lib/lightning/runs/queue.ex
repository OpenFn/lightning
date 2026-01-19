defmodule Lightning.Runs.Queue do
  @moduledoc """
  Allows adding, removing or claiming work to be executed by the Runtime.
  """
  import Ecto.Query

  alias Lightning.Repo
  alias Lightning.Runs

  @spec claim(non_neg_integer(), Ecto.Query.t(), String.t() | nil) ::
          {:ok, [Lightning.Run.t()]}
          | {:error, Ecto.Changeset.t(Lightning.Run.t())}
  def claim(demand, base_query, worker_name \\ nil) do
    Ecto.Multi.new()
    |> Ecto.Multi.run(:configure_session, fn repo, _changes ->
      work_mem = Lightning.Config.claim_work_mem()

      with {:ok, _} <-
             repo.query("SET LOCAL plan_cache_mode = force_custom_plan"),
           {:ok, _} <- maybe_set_work_mem(repo, work_mem) do
        {:ok, :session_configured}
      end
    end)
    |> Ecto.Multi.run(:claim_runs, fn _repo, _changes ->
      subset_query =
        base_query
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

      Runs.update_runs(query,
        set: [
          state: :claimed,
          claimed_at: DateTime.utc_now(),
          worker_name: worker_name
        ]
      )
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{claim_runs: %{runs: {_count, runs}}}} ->
        {:ok, runs}

      {:error, _op, changeset, _changes} ->
        {:error, changeset}
    end
  end

  defp maybe_set_work_mem(_repo, nil), do: {:ok, :skipped}

  defp maybe_set_work_mem(repo, work_mem),
    do: repo.query("SET LOCAL work_mem = '#{work_mem}'")
end
