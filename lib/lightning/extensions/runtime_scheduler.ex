defmodule Lightning.Extensions.RuntimeScheduler do
  @moduledoc """
  Adapter to call the extension for selecting Runtime workloads.
  """
  @behaviour Lightning.Extensions.RuntimeScheduling

  import Lightning.Extensions.AdapterHelper

  @impl true
  def enqueue(run) do
    adapter().enqueue(run)
  end

  @impl true
  def claim(demand) do
    adapter().claim(demand)
  end

  @impl true
  def dequeue(run) do
    adapter().dequeue(run)
  end

  defp adapter, do: adapter(:runtime_scheduler)
end
