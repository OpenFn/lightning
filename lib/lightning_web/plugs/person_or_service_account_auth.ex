defmodule LightningWeb.Plugs.PersonOrServiceAccountAuth do
  @moduledoc """
  Authenticates a request by either a service account's access token or the
  bearer tokens `LightningWeb.UserAuth` accepts (a personal access token or a
  repo connection token).

  A valid service-account token assigns the service account as
  `:current_resource` and the token's claims as `:access_token`; a
  service-account token that fails verification is refused as RFC 6750 §3
  says. Any other request gets exactly the answer `UserAuth.authenticate_bearer/2` and
  `UserAuth.require_authenticated_api_resource/2` give it elsewhere.

  `require_scope/2` holds a service account to the scope a controller names.
  Personal access tokens and repo connections carry no scopes, so it lets them
  through and leaves the decision to the controller's policy.
  """
  import Plug.Conn

  alias Lightning.ServiceAccount
  alias LightningWeb.Plugs.AccessTokenAuth
  alias LightningWeb.UserAuth

  def init(opts), do: opts

  def call(conn, _opts) do
    case AccessTokenAuth.service_account(conn) do
      {:ok, service_account, claims} ->
        conn
        |> assign(:current_resource, service_account)
        |> assign(:access_token, claims)

      {:error, :invalid_token} ->
        AccessTokenAuth.refuse(conn, 401, "invalid_token")

      :not_an_access_token ->
        conn
        |> UserAuth.authenticate_bearer([])
        |> UserAuth.require_authenticated_api_resource([])
    end
  end

  def require_scope(
        %Plug.Conn{assigns: %{current_resource: %ServiceAccount{}}} = conn,
        scope
      ),
      do: AccessTokenAuth.require_scope(conn, scope)

  def require_scope(conn, _scope), do: conn
end
