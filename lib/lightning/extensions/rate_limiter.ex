defmodule Lightning.Extensions.RateLimiter do
  @moduledoc """
  Adapter to call the extension for rate limiting.
  """
  @behaviour LightningExtensions.RateLimiting

  import Lightning.Extensions.AdapterHelper

  alias LightningExtensions.RateLimiting
  alias LightningExtensions.RateLimiting.Context
  alias Plug.Conn

  @spec limit_request(Conn.t(), Context.t()) ::
          :ok | {:error, RateLimiting.request_error(), String.t()}

  def limit_request(conn, context) do
    adapter().limit_request(conn, context)
  end

  defp adapter, do: adapter(:rate_limiter)
end
