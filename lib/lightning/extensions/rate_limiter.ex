defmodule Lightning.Extensions.RateLimiter do
  @moduledoc """
  Adapter to call the extension for rate limiting.
  """
  @behaviour LightningExtensions.RateLimiting

  import Lightning.Extensions.AdapterHelper

  alias LightningExtensions.RateLimiting
  alias LightningExtensions.RateLimiting.Action
  alias LightningExtensions.RateLimiting.Context
  alias Plug.Conn

  @spec check_limits(Context.t()) ::
          :ok | {:error, RateLimiting.limit_error(), String.t()}

  def check_limits(context) do
    adapter().check_limits(context)
  end

  @spec limit_request(Conn.t(), Context.t()) ::
          :ok | {:error, RateLimiting.request_error(), String.t()}

  def limit_request(conn, context) do
    adapter().limit_request(conn, context)
  end

  @spec limit_internal(Action.t(), Context.t()) ::
          :ok | {:error, RateLimiting.action_error(), String.t()}
  def limit_internal(action, context) do
    adapter().limit_internal(action, context)
  end

  defp adapter, do: adapter(:rate_limiter)
end
