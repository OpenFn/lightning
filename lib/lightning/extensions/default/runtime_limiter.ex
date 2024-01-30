defmodule Lightning.Extensions.Default.RuntimeLimiter do
  @moduledoc """
  Runtime limiting stub for Lightning.
  """
  @behaviour Lightning.Extensions.RuntimeLimiting

  def check_limits(_context) do
    :ok
  end

  def limit_internal(_action, _context) do
    :ok
  end
end
