defmodule Lightning.Extensions.FifoRunQueue do
  @moduledoc """
  Allows adding, removing or claiming work to be executed by the Runtime.
  """

  @behaviour Lightning.Extensions.RunQueue

  import Ecto.Query

  alias Lightning.Repo
  alias Lightning.Runs.Queue

  @impl true
  def enqueue(run) do
    run
    |> Repo.insert()
  end

  @impl true
  def claim(demand) do
    fifo_runs_query =
      Lightning.Run
      |> order_by([:priority, :inserted_at])

    Queue.claim(demand, fifo_runs_query)
  end

  @impl true
  def dequeue(run) do
    run
    |> Repo.delete()
  end
end
