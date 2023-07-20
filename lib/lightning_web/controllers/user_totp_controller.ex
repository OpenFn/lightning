defmodule LightningWeb.UserTOTPController do
  use LightningWeb, :controller

  alias Lightning.Accounts
  alias LightningWeb.UserAuth

  plug :redirect_if_totp_is_not_pending

  @totp_session :user_totp_pending

  def new(conn, params) do
    render(conn, "new.html",
      error_message: nil,
      remember_me: params["user"]["remember_me"]
    )
  end

  def create(conn, %{"user" => params}) do
    current_user = conn.assigns.current_user

    if Accounts.valid_user_totp?(current_user, params["code"]) do
      conn
      |> delete_session(@totp_session)
      |> UserAuth.redirect_user_after_login_with_remember_me(params)
    else
      render(conn, "new.html",
        remember_me: params["remember_me"],
        error_message: "Invalid two-factor authentication code"
      )
    end
  end

  defp redirect_if_totp_is_not_pending(conn, _opts) do
    if get_session(conn, @totp_session) do
      conn
    else
      conn
      |> redirect(to: "/")
      |> halt()
    end
  end
end
