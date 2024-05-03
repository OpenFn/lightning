defmodule LightningWeb.Plugs.RegisterGatekeeper do
  @moduledoc """
  Plug to conditionally render a 404 page if sign-up is disabled,
  otherwise continue.
  """
  import Plug.Conn
  use Phoenix.Controller

  def init(opts), do: opts

  def call(%Plug.Conn{request_path: "/users/register"} = conn, _opts) do
    if Application.get_env(:lightning, :disable_registration) do
      conn
      |> put_status(:not_found)
      |> put_resp_content_type("text/plain")
      |> text("404 Page not found")
      |> halt()
    else
      conn
    end
  end

  def call(conn, _opts), do: conn
end
