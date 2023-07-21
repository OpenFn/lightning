defmodule LightningWeb.UserTOTPController do
  use LightningWeb, :controller

  alias Lightning.Accounts
  alias LightningWeb.UserAuth

  plug :redirect_if_totp_is_not_pending

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
      |> UserAuth.totp_validated()
      |> UserAuth.redirect_with_return_to(params)
    else
      render(conn, "new.html",
        remember_me: params["remember_me"],
        error_message: "Invalid two-factor authentication code"
      )
    end
  end

  defp redirect_if_totp_is_not_pending(conn, _opts) do
    if UserAuth.totp_pending?(conn) do
      conn
    else
      conn
      |> redirect(to: "/")
      |> halt()
    end
  end
end
