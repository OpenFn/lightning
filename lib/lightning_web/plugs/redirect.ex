defmodule LightningWeb.Plugs.Redirect do
  use Phoenix.Controller
  import Plug.Conn

  def init(opts) do
    opts
  end

  def call(conn, opts) do
    to = Keyword.fetch!(opts, :to)

    conn
    |> redirect(to: to)
    |> halt()
  end
end
