defmodule LightningWeb.ConnHelpers do
  def assign_bearer(conn, token) do
    conn |> Plug.Conn.put_req_header("authorization", "Bearer #{token}")
  end
end
