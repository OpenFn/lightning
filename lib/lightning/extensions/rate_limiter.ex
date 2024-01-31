defmodule Lightning.Extensions.RateLimiter do
  @moduledoc """
  Adapter to call the extension for rate limiting.
  """
  @behaviour Lightning.Extensions.RateLimiting

  import Lightning.Extensions.AdapterHelper

  alias Lightning.Extensions.RateLimiting
  alias Lightning.Extensions.RateLimiting.Context
  alias Plug.Conn

  @spec limit_request(Conn.t(), Context.t(), Keyword.t()) ::
          :ok | {:error, RateLimiting.request_error(), String.t()}

  def limit_request(conn, context, opts \\ []) do
    adapter().limit_request(conn, context, opts)
  end

  defp adapter, do: adapter(:rate_limiter)
end
