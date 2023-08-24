defmodule Lightning.Attempts do
  alias Lightning.Repo

  import Ecto.Query

  @doc """
  Enqueue an attempt to be processed.
  """
  def enqueue(%Lightning.Attempt{} = attempt) do
    attempt
    |> Repo.insert()
  end

  # @doc """
  # Claim an available attempt.

  # Returns `nil` if no attempt is available.
  # """
  def claim(demand \\ 1) do
    subset_query =
      Lightning.Attempt
      |> select([:id])
      |> where([j], j.state == "available")
      |> limit(^demand)
      |> order_by(asc: :inserted_at)
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
      Lightning.Attempt
      |> with_cte("subset", as: ^subset_query)
      |> join(:inner, [a], x in fragment(~s("subset")), on: true)
      |> where([a, x], a.id == x.id)
      |> select([a, _], a)

    updates = [
      set: [state: "claimed", claimed_at: DateTime.utc_now()]
    ]

    Repo.transaction(fn ->
      {_count, jobs} = Repo.update_all(query, updates)

      jobs
    end)
  end

  # @doc """
  # Removes an attempt from the queue.
  # """
  # def dequeue(attempt) do
  # end
end
