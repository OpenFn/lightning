defmodule Lightning.Extensions.RuntimeLimiter do
  @moduledoc """
  Runtime limiting stub for Lightning.
  """
  @behaviour Lightning.Extensions.RuntimeLimiting

  @impl true
  def check_limits(_context) do
    :ok
  end

  @impl true
  def limit_action(_action, _context) do
    :ok
  end
end
