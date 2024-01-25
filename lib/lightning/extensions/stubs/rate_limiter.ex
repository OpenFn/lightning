defmodule Lightning.Extensions.Stubs.RateLimiter do
  @moduledoc """
  Rate limiting stub for Lightning.
  """
  @behaviour LightningExtensions.RateLimiting

  def check_limits(_context) do
    :ok
  end

  def limit_request(_conn, _context) do
    :ok
  end

  def limit_internal(_action, _context) do
    :ok
  end
end
