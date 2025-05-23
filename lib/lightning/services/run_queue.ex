defmodule Lightning.Services.RunQueue do
  @moduledoc """
  Adapter to call the extension for selecting Runtime workloads.
  """
  @behaviour Lightning.Extensions.RunQueue

  import Lightning.Services.AdapterHelper

  @impl true
  def enqueue(run) do
    adapter().enqueue(run)
  end

  @impl true
  def enqueue_many(run) do
    adapter().enqueue_many(run)
  end

  @impl true
  def claim(demand, worker_name) do
    adapter().claim(demand, worker_name)
  end

  @impl true
  def dequeue(run) do
    adapter().dequeue(run)
  end

  defp adapter, do: adapter(:run_queue)
end
