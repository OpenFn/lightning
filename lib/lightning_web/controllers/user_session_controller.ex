defmodule LightningWeb.UserSessionController do
  use LightningWeb, :controller

  alias Lightning.Accounts
  alias Lightning.Accounts.User
  alias LightningWeb.UserAuth

  def new(conn, _params) do
    render(conn, "new.html",
      error_message: nil,
      auth_handler_url: auth_handler_url()
    )
  end

  def create(conn, %{"user" => user_params}) do
    %{"email" => email, "password" => password} = user_params

    Accounts.get_user_by_email_and_password(email, password)
    |> case do
      %User{disabled: true} ->
        conn
        |> put_flash(:error, "This user account is disabled")
        |> render("new.html", auth_handler_url: auth_handler_url())

      %User{scheduled_deletion: x} when x != nil ->
        conn
        |> put_flash(
          :error,
          "This user account is scheduled for deletion"
        )
        |> render("new.html", auth_handler_url: auth_handler_url())

      %User{mfa_enabled: true} = user ->
        totp_params = Map.take(user_params, ["remember_me"])

        conn
        |> UserAuth.log_in_user(user)
        |> UserAuth.mark_totp_pending()
        |> redirect(to: Routes.user_totp_path(conn, :new, user: totp_params))

      %User{} = user ->
        conn
        |> UserAuth.log_in_user(user)
        |> UserAuth.redirect_with_return_to(user_params)

      _ ->
        conn
        |> put_flash(:error, "Invalid email or password")
        |> render("new.html", auth_handler_url: auth_handler_url())
    end
  end

  def exchange_token(conn, %{"token" => token}) do
    case Accounts.exchange_auth_token(token |> Base.url_decode64!()) do
      nil ->
        conn
        |> put_flash(:error, "Invalid token")
        |> redirect(to: Routes.user_session_path(conn, :new))

      token ->
        conn
        |> UserAuth.new_session(token)
        |> UserAuth.redirect_with_return_to()
    end
  end

  def delete(conn, _params) do
    conn
    |> put_flash(:info, "Logged out successfully.")
    |> UserAuth.log_out_user()
  end

  def auth_handler_url do
    case Lightning.AuthProviders.get_handlers() do
      {:ok, []} ->
        nil

      {:ok, [handler | _rest]} ->
        Lightning.AuthProviders.get_authorize_url(handler)
    end
  end
end
