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

  @impl true
  def increment_ai_queries(session) do
    adapter().increment_ai_queries(session)
  end

  @impl true
  def get_run_options(context) do
    adapter().get_run_options(context)
  end

  @impl true
  def get_data_retention_periods(context) do
    adapter().get_data_retention_periods(context)
  end

  @impl true
  def get_data_retention_message(context) do
    adapter().get_data_retention_message(context)
  end

  defp adapter, do: adapter(:usage_limiter)
end
