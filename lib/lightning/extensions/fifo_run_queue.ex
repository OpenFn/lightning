defmodule Lightning.Extensions.FifoRunQueue do
  @moduledoc """
  Allows adding, removing or claiming work to be executed by the Runtime.
  """

  @behaviour Lightning.Extensions.RunQueue

  alias Ecto.Multi
  alias Lightning.Repo
  alias Lightning.Runs.Query
  alias Lightning.Runs.Queue

  @impl true
  def enqueue(%Multi{} = multi), do: Repo.transaction(multi)

  @impl true
  def enqueue_many(%Multi{} = multi), do: Repo.transaction(multi)

  @impl true
  def claim(demand, worker_name \\ nil) do
    fifo_runs_query = Query.eligible_for_claim()

    Queue.claim(demand, fifo_runs_query, worker_name)
  end

  @impl true
  def dequeue(run) do
    run
    |> Repo.delete()
  end
end
