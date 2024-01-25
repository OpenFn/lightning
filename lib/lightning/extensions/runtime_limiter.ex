defmodule Lightning.Extensions.RuntimeLimiter do
  @moduledoc """
  Adapter to call the extension for limiting Runtime workloads.
  """
  @behaviour LightningExtensions.RuntimeLimiting

  import Lightning.Extensions.AdapterHelper

  alias LightningExtensions.RuntimeLimiting.Action
  alias LightningExtensions.RuntimeLimiting.Context

  @spec check_limits(Context.t()) ::
          :ok | {:error, RateLimiting.limit_error(), String.t()}

  def check_limits(context) do
    adapter().check_limits(context)
  end

  @spec limit_internal(Action.t(), Context.t()) ::
          :ok | {:error, RateLimiting.action_error(), String.t()}
  def limit_internal(action, context) do
    adapter().limit_internal(action, context)
  end

  defp adapter, do: adapter(:runtime_limiter)
end
