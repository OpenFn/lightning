defmodule Lightning.Services.UsageLimiter do
  @moduledoc """
  Adapter to call the extension for limiting Runtime workloads.
  """
  @behaviour Lightning.Extensions.UsageLimiting

  import Lightning.Services.AdapterHelper

  @impl true
  def check_limits(context) do
    adapter().check_limits(context)
  end

  @impl true
  def limit_action(action, context) do
    adapter().limit_action(action, context)
  end

  defp adapter, do: adapter(:usage_limiter)
end
