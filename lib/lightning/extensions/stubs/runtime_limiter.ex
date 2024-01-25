defmodule Lightning.Extensions.Stubs.RuntimeLimiter do
  @moduledoc """
  Runtime limiting stub for Lightning.
  """
  @behaviour LightningExtensions.RuntimeLimiting

  def check_limits(_context) do
    :ok
  end

  def limit_internal(_action, _context) do
    :ok
  end
end
