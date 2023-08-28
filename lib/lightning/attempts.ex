defmodule Lightning.Attempts.Adaptor do
  @doc """
  Enqueue an attempt to be processed.
  """
  @callback enqueue(
              attempt ::
                Lightning.Attempt.t() | Ecto.Changeset.t(Lightning.Attempt.t())
            ) ::
              {:ok, Lightning.Attempt.t()}

  # @doc """
  # Claim an available attempt.

  # Returns `nil` if no attempt is available.
  # """
  @callback claim(demand :: non_neg_integer()) :: {:ok, [Lightning.Attempt.t()]}
  # @callback dequeue(attempt :: Lightning.Attempt.t()) :: Lightning.Attempt.t()
end

defmodule Lightning.Attempts.Pipeline do
  @behaviour Lightning.Attempts.Adaptor

  alias Lightning.{AttemptService, Repo}
  alias Lightning.Invocation.Run

  @doc """
  Enqueue an attempt to be processed.
  """
  @impl true
  def enqueue(attempt) do
    Repo.transact(fn ->
      with {:ok, attempt} <- Repo.insert(attempt),
           %{reason: %{dataclip_id: dataclip_id, trigger: trigger}} <-
             attempt
             |> Repo.preload(reason: [trigger: [edges: [:target_job]]]),

           # find the edge for a trigger, and then find the job for that edge
           job when not is_nil(job) <-
             trigger.edges |> List.first() |> Map.get(:target_job),
           {:ok, attempt_run} <-
             AttemptService.append(
               attempt,
               Run.new(%{
                 job_id: job.id,
                 input_dataclip_id: dataclip_id
               })
             ) do
        %{attempt_run_id: attempt_run.id}
        |> Lightning.Pipeline.new()
        |> Lightning.Pipeline.enqueue()

        {:ok, attempt}
      end
    end)
  end

  @impl true
  def claim(_demand \\ 1) do
    {:ok, []}
  end
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

  defp adaptor do
    Lightning.Config.attempts_adaptor()
  end

  # @doc """
  # Removes an attempt from the queue.
  # """
  # def dequeue(attempt) do
  # end
end
