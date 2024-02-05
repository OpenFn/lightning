defmodule Lightning.Extensions.Default.RuntimeScheduler do
  @moduledoc """
  Default implementation of runtime scheduler.
  """

  @behaviour Lightning.Extensions.RuntimeScheduling

  alias Lightning.Runs.Queue

  @impl true
  def enqueue(run) do
    Queue.enqueue(run)
  end

  @impl true
  def claim(demand) do
    Queue.claim(demand)
  end

  @impl true
  def dequeue(run) do
    Queue.dequeue(run)
  end
end
