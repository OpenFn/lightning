defmodule LightningWeb.Plugs.PersonOrServiceAccountAuth do
  @moduledoc """
  Authenticates a request by a service account's access token, the bearer
  tokens `LightningWeb.UserAuth` accepts (a personal access token or a repo
  connection token), or, when there is no `Authorization` header, the session
  token of Lightning's own app (`LightningWeb.SessionToken`).

  A token that declares itself an access token is checked only as one, and the
  service account it speaks for becomes `:current_resource`. Any other bearer
  token gets the answer `UserAuth.authenticate_bearer/2` and
  `UserAuth.require_authenticated_api_resource/2` give it.

  A session token counts only on a request from Lightning's own pages, only
  once its person is fully signed in (MFA done, account not shut out pending
  confirmation), and on a write only with the session's `x-csrf-token`. One
  that fails the first two is no token at all, so the request is refused as if
  it sent nothing. A write without the CSRF token is 400 `invalid_header`.
  It then acts as the person, as a personal access token does.

  It also assigns `:token_kind`, and `:stepped_up_until` for a session, which
  `LightningWeb.Plugs.AuthorizeAction` puts on the `Lightning.Scope`.

  It only authenticates. The policies decide what the caller may do, including
  whether its token holds the grant an action needs, or is a session token.
  """
  import Plug.Conn, only: [assign: 3, get_req_header: 2]

  alias Lightning.Accounts.User
  alias Lightning.ServiceAccount.AccessToken
  alias Lightning.VersionControl.ProjectRepoConnection
  alias LightningWeb.API.Problem
  alias LightningWeb.Auth
  alias LightningWeb.SessionToken
  alias LightningWeb.UserAuth

  def init(opts), do: opts

  def call(conn, _opts) do
    with {:ok, token} <- Auth.bearer_token(conn),
         true <- AccessToken.access_token?(token) do
      authenticate_service_account(conn, token)
    else
      {:error, :missing} ->
        if get_req_header(conn, "authorization") == [],
          do: authenticate_session(conn),
          else: authenticate_person(conn)

      _person ->
        authenticate_person(conn)
    end
  end

  defp authenticate_service_account(conn, token) do
    case AccessToken.verify(token) do
      {:ok, service_account} ->
        conn
        |> assign(:current_resource, service_account)
        |> assign(:token_kind, :access_token)

      {:error, :expired} ->
        Auth.refuse(conn, :bearer, :expired)

      {:error, :invalid} ->
        Auth.refuse(conn, :bearer)
    end
  end

  defp authenticate_person(conn) do
    conn
    |> UserAuth.authenticate_bearer([])
    |> UserAuth.require_authenticated_api_resource([])
    |> assign_bearer_kind()
  end

  defp assign_bearer_kind(%Plug.Conn{halted: true} = conn), do: conn

  defp assign_bearer_kind(conn) do
    case conn.assigns.current_resource do
      %User{} -> assign(conn, :token_kind, :personal_access_token)
      %ProjectRepoConnection{} -> assign(conn, :token_kind, :repo_connection)
    end
  end

  defp authenticate_session(conn) do
    case SessionToken.read(conn) do
      {%{state: :signed_in} = session, conn} ->
        case SessionToken.check_csrf(conn) do
          :ok ->
            conn
            |> assign(:current_resource, session.user)
            |> assign(:token_kind, :session)
            |> assign(:stepped_up_until, session.stepped_up_until)

          {:error, problem} ->
            Problem.halt(conn, problem)
        end

      {_no_session, conn} ->
        Auth.refuse(conn, :bearer)
    end
  end
end
