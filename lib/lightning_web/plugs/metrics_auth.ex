defmodule LightningWeb.Plugs.MetricsAuth do
  import Plug.Conn

  def call(conn, _opts) do
    conn
    |> put_resp_header("www-authenticate", "Bearer")
    |> send_resp(401, "Unauthorized")
    |> halt()
    # conn |> put_status(:unauthorized) |> put_resp_header("www-authenticate", "Bearer") |> halt()
  end
end
