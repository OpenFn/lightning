defmodule Lightning.Extensions.RateLimiter do
  @moduledoc """
  Rate limiting stub for Lightning.
  """
  @behaviour Lightning.Extensions.RateLimiting

  @impl true
  def limit_request(_conn, _context, _opts) do
    :ok
  end
end
