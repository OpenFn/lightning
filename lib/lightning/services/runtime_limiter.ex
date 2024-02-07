defmodule Lightning.Services.RuntimeLimiter do
  @moduledoc """
  Adapter to call the extension for limiting Runtime workloads.
  """
  @behaviour Lightning.Extensions.RuntimeLimiting

  import Lightning.Services.AdapterHelper

  @impl true
  def check_limits(context) do
    adapter().check_limits(context)
  end

  @impl true
  def limit_action(action, context) do
    adapter().limit_action(action, context)
  end

  defp adapter, do: adapter(:runtime_limiter)
end
