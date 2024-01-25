defmodule Lightning.Extensions.Stubs.RateLimiter do
  @moduledoc """
  Rate limiting stub for Lightning.
  """
  @behaviour LightningExtensions.RateLimiting

  def limit_request(_conn, _context) do
    :ok
  end
end
