defmodule LightningWeb.OidcController do
  use LightningWeb, :controller

  alias Lightning.AuthProviders
  alias Lightning.AuthProviders.Handler
  alias Lightning.Accounts
  alias LightningWeb.UserAuth

  action_fallback LightningWeb.FallbackController

  plug :fetch_current_user

  def show(conn, %{"provider" => provider}) do
    with {:ok, handler} <- AuthProviders.get_handler(provider) do
      if conn.assigns.current_user do
        UserAuth.redirect_if_user_is_authenticated(conn, nil)
      else
        authorize_url = Handler.authorize_url(handler)
        redirect(conn, external: authorize_url)
      end
    end
  end

  def new(conn, %{"provider" => provider, "code" => code}) do
    with {:ok, handler} <- AuthProviders.get_handler(provider),
         {:ok, token} <- Handler.get_token(handler, code) do
      userinfo = Handler.get_userinfo(handler, token)
      email = Map.fetch!(userinfo, "email")

      case Accounts.get_user_by_email(email) do
        nil ->
          conn
          |> put_flash(:error, "Could not find user account")
          |> redirect(to: Routes.user_session_path(conn, :new))

        user ->
          conn |> UserAuth.log_in_user(user, %{"remember_me" => "true"})
      end
    end
  end
end
