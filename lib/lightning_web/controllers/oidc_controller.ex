defmodule LightningWeb.OidcController do
  use LightningWeb, :controller

  alias Lightning.Accounts
  alias Lightning.AuthProviders
  alias Lightning.AuthProviders.Handler
  alias LightningWeb.OauthCredentialHelper
  alias LightningWeb.UserAuth

  action_fallback LightningWeb.FallbackController

  plug :fetch_current_user

  @doc """
  Given a known provider, redirect them to the authorize url on the provider
  """
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

  @doc """
  Once the user has completed the authorization flow from above, they are
  returned here, and the authorization code is used to log them in.
  """
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

        %{mfa_enabled: true} = user ->
          conn
          |> UserAuth.log_in_user(user)
          |> UserAuth.mark_totp_pending()
          |> redirect(
            to:
              Routes.user_totp_path(conn, :new, user: %{"remember_me" => "true"})
          )

        user ->
          conn
          |> UserAuth.log_in_user(user)
          |> UserAuth.redirect_with_return_to(%{
            "remember_me" => "true"
          })
      end
    end
  end

  def new(conn, %{"state" => state, "code" => code}) do
    [subscription_id, mod, component_id] =
      OauthCredentialHelper.decode_state(state)

    OauthCredentialHelper.broadcast_forward(subscription_id, mod,
      id: component_id,
      code: code
    )

    html(conn, """
      <html>
        <body>
          <script type="text/javascript">
            window.onload = function() {
              window.close();
            }
          </script>
        </body>
      </html>
    """)
  end
end
