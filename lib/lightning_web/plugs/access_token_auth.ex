defmodule LightningWeb.Plugs.AccessTokenAuth do
  @moduledoc """
  Authenticates a request by a service account's access token, and refuses
  every other kind of token.

  `call/2` goes in the pipeline. It accepts only tokens issued to the service
  account registered now, so unsetting `SERVICE_ACCOUNT_PUBLIC_KEY` cuts off
  tokens already issued. It assigns the token's claims as `:access_token`, and
  the service account as `:current_resource` with the token's scopes as its
  `grants`. It only authenticates. The policies decide whether those grants
  allow an action. Refusals follow RFC 6750 §3.
  """
  import Plug.Conn

  alias Lightning.ServiceAccount
  alias Lightning.ServiceAccount.AccessToken
  alias LightningWeb.API.Challenge

  def init(opts), do: opts

  def call(conn, _opts) do
    with ["Bearer " <> token] <- get_req_header(conn, "authorization"),
         {:ok, %{"sub" => sub} = claims} <- AccessToken.verify(token),
         %ServiceAccount{id: ^sub} = service_account <-
           Lightning.Config.service_account() do
      grants = claims |> Map.get("scope", "") |> String.split() |> MapSet.new()

      conn
      |> assign(:access_token, claims)
      |> assign(:current_resource, %{service_account | grants: grants})
    else
      _other -> refuse(conn)
    end
  end

  defp refuse(conn) do
    conn
    |> merge_resp_headers([Challenge.invalid_token()])
    |> put_status(401)
    |> Phoenix.Controller.json(%{error: "invalid_token"})
    |> halt()
  end
end
