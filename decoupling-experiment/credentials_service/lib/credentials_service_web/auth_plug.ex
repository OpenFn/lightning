defmodule CredentialsServiceWeb.AuthPlug do
  @moduledoc """
  Request-level authentication.

  This is the architectural change the decoupling requires: authorization moves
  OUT of LiveView `on_mount`/inline handlers and INTO a plug that runs per
  request. In Lightning this is `LightningWeb.Plugs.ApiAuth` verifying a JWT via
  `Lightning.Tokens`. For the slice the bearer token IS the user's UUID, a
  deliberate stand-in so tests need no key material. The boundary shape is the
  point, not the token format.
  """
  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    case get_req_header(conn, "authorization") do
      ["Bearer " <> user_id] when byte_size(user_id) > 0 ->
        assign(conn, :current_user_id, user_id)

      _ ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(401, Jason.encode!(%{errors: %{detail: "Unauthorized"}}))
        |> halt()
    end
  end
end
