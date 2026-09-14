defmodule LightningWeb.Plugs.BlockRoutes do
  @moduledoc """
  Plug to conditionally block specified routes based on configuration flags and custom messages.
  """
  use Phoenix.Controller
  import Plug.Conn

  def init(opts) do
    opts
  end

  def call(%Plug.Conn{path_info: path_info} = conn, routes_flags) do
    case get_route_flag_and_message(normalize(path_info), routes_flags) do
      {:block, message} ->
        conn
        |> put_status(:not_found)
        |> put_resp_content_type("text/plain")
        |> text(message)
        |> halt()

      :allow ->
        conn
    end
  end

  defp get_route_flag_and_message(path_segments, routes_flags) do
    Enum.find_value(routes_flags, :allow, fn {route, flag, message} ->
      if path_matches?(path_segments, segments(route)) do
        if Lightning.Config.check_flag?(flag) do
          :allow
        else
          {:block, message}
        end
      else
        :allow
      end
    end)
  end

  # Decide on the same canonical path the router dispatches on, not the raw
  # request target. `conn.path_info` already has empty segments dropped by the
  # adapter, but it is *not* percent-decoded until the router matches — see
  # `Enum.map(path_info, &URI.decode/1)` in Phoenix.Router.call/2. We apply the
  # same per-segment decode here so alternate spellings such as `//users/register`
  # or `/users/%72egister` cannot slip past a rule that the router will still
  # match. A segment that fails to decode is left as-is; such a request raises
  # MalformedURIError in the router and never reaches a controller anyway.
  defp normalize(path_info) do
    Enum.map(path_info, fn segment ->
      try do
        URI.decode(segment)
      rescue
        ArgumentError -> segment
      end
    end)
  end

  # Split a configured route into segments the same way the adapter builds
  # `path_info` (dropping empty segments), so a rule is compared like-for-like.
  defp segments(route) do
    for segment <- String.split(route, "/"), segment != "", do: segment
  end

  # Prefix match on segments preserves the original subtree semantics (a rule for
  # `/users/register` also guards everything beneath it) without the false matches
  # a raw string prefix allowed (e.g. `/users/registered`).
  defp path_matches?(path_segments, route_segments) do
    Enum.take(path_segments, length(route_segments)) == route_segments
  end
end
