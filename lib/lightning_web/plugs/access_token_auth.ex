defmodule LightningWeb.Plugs.AccessTokenAuth do
  @moduledoc """
  Authenticates a request by a service account's access token, and refuses
  every other kind of token.

  `call/2` goes in the pipeline. It accepts only tokens issued to the service
  account registered now, so unsetting `SERVICE_ACCOUNT_PUBLIC_KEY` cuts off
  tokens already issued, and assigns the token's claims as `:access_token` and
  the service account as `:service_account`. Each controller then names the scope its actions need with
  `plug :require_scope, "users:read"`. Refusals follow RFC 6750 §3.
  """
  import Plug.Conn

  alias Lightning.ServiceAccount
  alias Lightning.ServiceAccount.AccessToken

  def init(opts), do: opts

  def call(conn, _opts) do
    with ["Bearer " <> token] <- get_req_header(conn, "authorization"),
         {:ok, %{"sub" => sub} = claims} <- AccessToken.verify(token),
         %ServiceAccount{id: ^sub} = service_account <-
           Lightning.Config.service_account() do
      conn
      |> assign(:access_token, claims)
      |> assign(:service_account, service_account)
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
