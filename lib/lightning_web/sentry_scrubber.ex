defmodule LightningWeb.SentryScrubber do
  @moduledoc """
  Request header scrubbing for `Sentry.PlugContext`, wired up in
  `LightningWeb.Endpoint`.
  """

  @extra_sensitive_headers ~w(x-api-key proxy-authorization)

  @doc """
  Drops Sentry's default sensitive headers, then ours. Returns a map, as
  `Sentry.PlugContext.default_header_scrubber/1` does.
  """
  @spec scrub_headers(Plug.Conn.t()) :: map()
  def scrub_headers(%Plug.Conn{} = conn) do
    conn
    |> Sentry.Scrubber.scrub(:headers)
    |> Enum.reject(fn
      {name, _value} when is_binary(name) ->
        String.downcase(name) in @extra_sensitive_headers

      _other ->
        false
    end)
    |> Map.new()
  end
end
