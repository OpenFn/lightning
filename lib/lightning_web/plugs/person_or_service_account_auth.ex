defmodule LightningWeb.Plugs.PersonOrServiceAccountAuth do
  @moduledoc """
  Authenticates a request by either a service account's access token or the
  bearer tokens `LightningWeb.UserAuth` accepts (a personal access token or a
  repo connection token).

  A token that declares itself an access token goes to
  `LightningWeb.Plugs.AccessTokenAuth` and must carry the `scope:` this plug is
  given. Any other request gets exactly the answer
  `UserAuth.authenticate_bearer/2` and
  `UserAuth.require_authenticated_api_resource/2` give it elsewhere.

  A resource opts in by adding a router pipeline that names its scope:

      plug LightningWeb.Plugs.PersonOrServiceAccountAuth, scope: "projects:write"

  A person's token carries no scopes, so the scope binds service accounts
  only; for a person, the controller's policy decides.
  """
  alias Lightning.ServiceAccount.AccessToken
  alias LightningWeb.Plugs.AccessTokenAuth
  alias LightningWeb.UserAuth

  def init(opts), do: Keyword.fetch!(opts, :scope)

  def call(conn, scope) do
    with {:ok, token} <- UserAuth.get_bearer(conn),
         true <- AccessToken.access_token?(token) do
      conn = AccessTokenAuth.call(conn, [])

      if conn.halted, do: conn, else: AccessTokenAuth.require_scope(conn, scope)
    else
      _person ->
        conn
        |> UserAuth.authenticate_bearer([])
        |> UserAuth.require_authenticated_api_resource([])
    end
  end
end
