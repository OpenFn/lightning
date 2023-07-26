defmodule LightningWeb.UserTOTPController do
  use LightningWeb, :controller

  alias Lightning.Accounts
  alias LightningWeb.UserAuth

  plug :redirect_if_totp_is_not_pending

  def new(conn, params) do
    render(conn, "new.html",
      error_message: nil,
      remember_me: params["user"]["remember_me"],
      authentication_type: authentication_type(params["authentication_type"])
    )
  end

  def create(conn, %{"user" => params}) do
    current_user = conn.assigns.current_user

    if valid_user_code?(current_user, params) do
      conn
      |> UserAuth.totp_validated()
      |> UserAuth.redirect_with_return_to(params)
    else
      render(conn, "new.html",
        remember_me: params["remember_me"],
        authentication_type: params["authentication_type"],
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

  defp authentication_type(type) do
    case type do
      "backup_code" ->
        :backup_code

      _other ->
        :totp
    end
  end

  defp valid_user_code?(user, %{
         "code" => code,
         "authentication_type" => "backup_code"
       }) do
    Accounts.valid_user_backup_code?(user, code)
  end

  defp valid_user_code?(user, %{
         "code" => code,
         "authentication_type" => "totp"
       }) do
    Accounts.valid_user_totp?(user, code)
  end
end
