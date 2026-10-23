defmodule LightningWeb.Plugs.AccessTokenAuth do
  @moduledoc """
  Authenticates a request by a service account's access token, and refuses
  every other kind of token.

  `call/2` goes in the pipeline. It accepts only tokens issued to the service
  account registered now, so unsetting `SERVICE_ACCOUNT_PUBLIC_KEY` cuts off
  tokens already issued. It assigns the token's claims as `:access_token`, and
  the service account as `:current_resource` with the token's scopes as its
  `grants`. It only authenticates. The policies decide whether those grants
  allow an action. A refusal is `LightningWeb.Auth`'s.
  """
  import Plug.Conn

  alias Lightning.ServiceAccount
  alias Lightning.ServiceAccount.AccessToken
  alias LightningWeb.Auth

  def init(opts), do: opts

  def call(conn, _opts) do
    with {:ok, token} <- Auth.bearer_token(conn),
         {:ok, %{"sub" => sub} = claims} <- AccessToken.verify(token),
         %ServiceAccount{id: ^sub} = service_account <-
           Lightning.Config.service_account() do
      grants = claims |> Map.get("scope", "") |> String.split() |> MapSet.new()

      conn
      |> assign(:access_token, claims)
      |> assign(:current_resource, %{service_account | grants: grants})
    else
      _other -> Auth.refuse(conn, :bearer)
    end
  end
end
