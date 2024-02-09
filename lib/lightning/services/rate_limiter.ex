defmodule Lightning.Services.RateLimiter do
  @moduledoc """
  Adapter to call the extension for rate limiting.
  """
  @behaviour Lightning.Extensions.RateLimiting

  import Lightning.Services.AdapterHelper

  @impl true
  def limit_request(conn, context, opts) do
    adapter().limit_request(conn, context, opts)
  end

  defp adapter, do: adapter(:rate_limiter)
end
