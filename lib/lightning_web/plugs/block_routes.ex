defmodule LightningWeb.Plugs.BlockRoutes do
  @moduledoc """
  Plug to conditionally block specified routes based on configuration flags and custom messages.
  """
  use Phoenix.Controller
  import Plug.Conn

  def init(opts) do
    opts
  end

  def call(%Plug.Conn{request_path: path} = conn, routes_flags) do
    case get_route_flag_and_message(path, routes_flags) do
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

  defp get_route_flag_and_message(path, routes_flags) do
    Enum.find_value(routes_flags, :allow, fn {route, flag, message} ->
      if String.starts_with?(path, route) do
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
end
