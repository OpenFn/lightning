defmodule Lightning.Attempts.Adaptor do
  @moduledoc """
  Behaviour for implementing an adaptor for the Lightning.Attempts module.
  """

  @doc """
  Enqueue an attempt to be processed.
  """
  @callback enqueue(
              attempt ::
                Lightning.Attempt.t() | Ecto.Changeset.t(Lightning.Attempt.t())
            ) ::
              {:ok, Lightning.Attempt.t()}
              | {:error, Ecto.Changeset.t(Lightning.Attempt.t())}

  # @doc """
  # Claim an available attempt.
  #
  # The `demand` parameter is used to request more than a since attempt,
  # all implementation should default to 1.
  # """
  @callback claim(demand :: non_neg_integer()) :: {:ok, [Lightning.Attempt.t()]}

  # @doc """
  # Removes an attempt from the queue.
  # """
  @callback dequeue(attempt :: Lightning.Attempt.t()) ::
              {:ok, Lightning.Attempt.t()}

  # @doc """
  # Marks an attempt as resolved.
  # """
  @callback resolve(attempt :: Lightning.Attempt.t()) ::
              {:ok, Lightning.Attempt.t()}
end

defmodule Lightning.Attempts.Queue do
  @behaviour Lightning.Attempts.Adaptor

  alias Lightning.{Repo}
  import Ecto.Query

  @impl true
  def enqueue(attempt) do
    attempt
    |> Repo.insert()
  end

  @impl true
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

  @impl true
  def resolve(attempt) do
    attempt
    |> Ecto.Changeset.change()
    |> Ecto.Changeset.put_change(:state, "resolved")
    |> Ecto.Changeset.put_change(:resolved_at, DateTime.utc_now())
    |> Repo.update()
  end

  @impl true
  def dequeue(attempt) do
    attempt
    |> Repo.delete()
  end
end

defmodule Lightning.Attempts do
  @behaviour Lightning.Attempts.Adaptor

  @impl true
  def enqueue(attempt) do
    adaptor().enqueue(attempt)
  end

  @impl true
  def claim(demand \\ 1) do
    adaptor().claim(demand)
  end

  @impl true
  def resolve(attempt) do
    adaptor().resolve(attempt)
  end

  @impl true
  def dequeue(attempt) do
    adaptor().dequeue(attempt)
  end

  defp adaptor do
    Lightning.Config.attempts_adaptor()
  end

  # @doc """
  # Removes an attempt from the queue.
  # """
  # def dequeue(attempt) do
  # end
end
