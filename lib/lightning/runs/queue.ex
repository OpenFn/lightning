defmodule Lightning.Runs.Queue do
  @moduledoc """
  Allows adding, removing or claiming work to be executed by the Runtime.
  """
  @behaviour Lightning.Runs.Adaptor

  import Ecto.Query

  alias Lightning.Runs
  alias Lightning.Repo

  @impl true
  def enqueue(run) do
    run
    |> Repo.insert()
  end

  @impl true
  def claim(demand \\ 1) do
    subset_query =
      Lightning.Run
      |> select([:id])
      |> where([j], j.state == :available)
      |> limit(^demand)
      |> order_by([:priority, :inserted_at])
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

  @impl true
  def dequeue(run) do
    run
    |> Repo.delete()
  end
end
