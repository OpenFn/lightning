defmodule Lightning.Extensions.Default.RateLimiter do
  @moduledoc """
  Rate limiting stub for Lightning.
  """
  @behaviour Lightning.Extensions.RateLimiting

  def limit_request(_conn, _context, _opts) do
    :ok
  end
end
