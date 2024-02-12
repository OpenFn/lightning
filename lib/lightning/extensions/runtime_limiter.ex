defmodule Lightning.Extensions.UsageLimiter do
  @moduledoc """
  Runtime limiting stub for Lightning.
  """
  @behaviour Lightning.Extensions.UsageLimiting

  @impl true
  def check_limits(_context) do
    :ok
  end

  @impl true
  def limit_action(_action, _context) do
    :ok
  end
end
