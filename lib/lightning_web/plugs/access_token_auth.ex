defmodule LightningWeb.Plugs.AccessTokenAuth do
  @moduledoc """
  Authenticates a request by a service account's access token, and refuses
  every other kind of token.

  `call/2` goes in the pipeline and assigns the token's claims as
  `:access_token`. Each controller then names the scope its actions need with
  `plug :require_scope, "users:read"`. Refusals follow RFC 6750 §3.
  """
  import Plug.Conn

  alias Lightning.ServiceAccount.AccessToken

  def init(opts), do: opts

  def call(conn, _opts) do
    with ["Bearer " <> token] <- get_req_header(conn, "authorization"),
         {:ok, claims} <- AccessToken.verify(token) do
      assign(conn, :access_token, claims)
    else
      _other -> refuse(conn, 401, "invalid_token")
    end
  end

  def require_scope(conn, scope) do
    if scope in String.split(conn.assigns.access_token["scope"]),
      do: conn,
      else: refuse(conn, 403, "insufficient_scope")
  end

  defp refuse(conn, status, error) do
    conn
    |> put_resp_header("www-authenticate", ~s(Bearer error="#{error}"))
    |> put_status(status)
    |> Phoenix.Controller.json(%{error: error})
    |> halt()
  end
end
