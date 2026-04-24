defmodule LightningWeb.Plugs.AdaptorIcons do
  @moduledoc """
  Intercepts requests for adaptor icons and the icon manifest before
  Plug.Static can serve stale filesystem copies.

  Sits before Plug.Static in the endpoint plug pipeline. Matches
  `GET /images/adaptors/*` and delegates to
  `LightningWeb.AdaptorIconController`.
  """
  @behaviour Plug

  import Plug.Conn

  @impl true
  def init(opts), do: opts

  @impl true
  def call(
        %Plug.Conn{
          method: "GET",
          path_info: ["images", "adaptors", "adaptor_icons.json"]
        } = conn,
        _opts
      ) do
    conn
    |> put_private(:plug_skip_csrf_protection, true)
    |> LightningWeb.AdaptorIconController.manifest(%{})
    |> halt()
  end

  def call(
        %Plug.Conn{
          method: "GET",
          path_info: ["images", "adaptors", icon]
        } = conn,
        _opts
      ) do
    conn
    |> put_private(:plug_skip_csrf_protection, true)
    |> LightningWeb.AdaptorIconController.show(%{"icon" => icon})
    |> halt()
  end

  def call(conn, _opts), do: conn
end
