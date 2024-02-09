defmodule Lightning.Runs.Queue do
  @moduledoc """
  Allows adding, removing or claiming work to be executed by the Runtime.
  """
  import Ecto.Query

  alias Lightning.Runs

  @spec claim(non_neg_integer(), Ecto.Query.t()) ::
          {:ok, [Lightning.Run.t()]}
          | {:error, Ecto.Changeset.t(Lightning.Run.t())}
  def claim(demand, base_query) do
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

    case Runs.update_runs(query,
           set: [state: :claimed, claimed_at: DateTime.utc_now()]
         ) do
      {:ok, %{runs: {_, runs}}} ->
        {:ok, runs}

      {:error, _op, changeset, _changes} ->
        {:error, changeset}
    end
  end
end
