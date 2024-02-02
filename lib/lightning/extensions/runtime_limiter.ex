defmodule Lightning.Extensions.RuntimeLimiter do
  @moduledoc """
  Adapter to call the extension for limiting Runtime workloads.
  """
  @behaviour Lightning.Extensions.RuntimeLimiting

  import Lightning.Extensions.AdapterHelper

  @type message :: %{
          position: atom(),
          function: fun(),
          attrs: Keyword.t()
        }

  @impl true
  def check_limits(context) do
    adapter().check_limits(context)
  end

  @impl true
  def limit_internal(action, context) do
    adapter().limit_internal(action, context)
  end

  defp adapter, do: adapter(:runtime_limiter)
end
