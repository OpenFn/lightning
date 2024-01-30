defmodule Lightning.Extensions.RuntimeLimiter do
  @moduledoc """
  Adapter to call the extension for limiting Runtime workloads.
  """
  @behaviour Lightning.Extensions.RuntimeLimiting

  import Lightning.Extensions.AdapterHelper

  alias Lightning.Extensions.RuntimeLimiting
  alias Lightning.Extensions.RuntimeLimiting.Action
  alias Lightning.Extensions.RuntimeLimiting.Context

  @type message :: %{
          position: atom(),
          function: fun(),
          attrs: Keyword.t()
        }

  @spec check_limits(Context.t()) ::
          :ok | {:error, RuntimeLimiting.limit_error(), message()}

  def check_limits(context) do
    adapter().check_limits(context)
  end

  @spec limit_internal(Action.t(), Context.t()) ::
          :ok | {:error, RuntimeLimiting.action_error(), String.t()}
  def limit_internal(action, context) do
    adapter().limit_internal(action, context)
  end

  defp adapter, do: adapter(:runtime_limiter)
end
