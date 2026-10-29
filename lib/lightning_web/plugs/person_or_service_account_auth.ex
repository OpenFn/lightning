defmodule LightningWeb.Plugs.PersonOrServiceAccountAuth do
  @moduledoc """
  Authenticates a request by either a service account's access token or the
  bearer tokens `LightningWeb.UserAuth` accepts (a personal access token or a
  repo connection token).

  A token that declares itself an access token goes to
  `LightningWeb.Plugs.AccessTokenAuth`. Any other request gets the answer
  `UserAuth.authenticate_bearer/2` and
  `UserAuth.require_authenticated_api_resource/2` give it.

  It only authenticates. The policies decide what the caller may do, including
  whether its token holds the grant an action needs.
  """
  alias Lightning.ServiceAccount.AccessToken
  alias LightningWeb.Auth
  alias LightningWeb.Plugs.AccessTokenAuth
  alias LightningWeb.UserAuth

  def init(opts), do: opts

  def call(conn, _opts) do
    with {:ok, token} <- Auth.bearer_token(conn),
         true <- AccessToken.access_token?(token) do
      AccessTokenAuth.call(conn, [])
    else
      _person ->
        conn
        |> UserAuth.authenticate_bearer([])
        |> UserAuth.require_authenticated_api_resource([])
    end
  end
end
