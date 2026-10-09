defmodule LightningWeb.Plugs.AccessTokenAuth do
  @moduledoc """
  Authenticates a request by a service account's access token, and refuses
  every other kind of token.

  `call/2` goes in the pipeline. It accepts only tokens issued to the service
  account registered now, so unsetting `SERVICE_ACCOUNT_PUBLIC_KEY` cuts off
  tokens already issued, and assigns the token's claims as `:access_token` and
  the service account as `:current_resource`. Each controller then names the
  scope its actions need with `plug :require_scope, "users:read"`. Refusals
  follow RFC 6750 §3.
  """
  import Plug.Conn

  alias Lightning.ServiceAccount
  alias Lightning.ServiceAccount.AccessToken

  def init(opts), do: opts

  def call(conn, _opts) do
    case service_account(conn) do
      {:ok, service_account, claims} ->
        conn
        |> assign(:access_token, claims)
        |> assign(:current_resource, service_account)

      _refused ->
        refuse(conn, 401, "invalid_token")
    end
  end

  @doc """
  The service account a request's bearer token was issued to, with the token's
  claims.

  `{:error, :invalid_token}` when the token is an access token by its `typ` but
  fails verification or names an account no longer registered, and
  `:not_an_access_token` when there is no bearer token or it is some other kind.
  """
  @spec service_account(Plug.Conn.t()) ::
          {:ok, ServiceAccount.t(), map()}
          | {:error, :invalid_token}
          | :not_an_access_token
  def service_account(conn) do
    with ["Bearer " <> token] <- get_req_header(conn, "authorization"),
         true <- AccessToken.access_token?(token) do
      verify(token)
    else
      _other -> :not_an_access_token
    end
  end

  defp verify(token) do
    with {:ok, %{"sub" => sub} = claims} <- AccessToken.verify(token),
         %ServiceAccount{id: ^sub} = service_account <-
           Lightning.Config.service_account() do
      {:ok, service_account, claims}
    else
      _other -> {:error, :invalid_token}
    end
  end

  def require_scope(conn, scope) do
    if scope in String.split(conn.assigns.access_token["scope"]),
      do: conn,
      else: refuse(conn, 403, "insufficient_scope")
  end

  @doc """
  Halts `conn` with an RFC 6750 §3 error response.
  """
  @spec refuse(Plug.Conn.t(), 401 | 403, String.t()) :: Plug.Conn.t()
  def refuse(conn, status, error) do
    conn
    |> put_resp_header("www-authenticate", ~s(Bearer error="#{error}"))
    |> put_status(status)
    |> Phoenix.Controller.json(%{error: error})
    |> halt()
  end
end
