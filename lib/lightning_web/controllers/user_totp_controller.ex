defmodule LightningWeb.UserTOTPController do
  use LightningWeb, :controller

  alias Lightning.Accounts.SignInAttempts
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
    user = conn.assigns.current_user
    token = get_session(conn, :user_token)

    case SignInAttempts.check_code(user, code(params), token) do
      :ok ->
        conn
        |> UserAuth.totp_validated()
        |> UserAuth.redirect_with_return_to(params)

      {:error, :invalid_credentials} ->
        refuse(conn, params, "Invalid two-factor authentication code")

      {:error, {:rate_limited, seconds}} ->
        conn
        |> UserAuth.too_many_attempts(seconds)
        |> refuse(params, UserAuth.too_many_attempts_message())

      {:error, :tries_spent} ->
        conn
        |> put_flash(:error, "Too many invalid codes. Please log in again.")
        |> UserAuth.log_out_user()
    end
  end

  defp refuse(conn, params, message) do
    render(conn, "new.html",
      remember_me: params["remember_me"],
      authentication_type: params["authentication_type"],
      error_message: message
    )
  end

  defp redirect_if_totp_is_not_pending(conn, _opts) do
    if UserAuth.totp_pending?(conn) do
      conn
    else
      conn
      |> redirect(to: "/projects")
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

  defp code(%{"code" => code, "authentication_type" => "backup_code"}),
    do: {:backup_code, code}

  defp code(%{"code" => code, "authentication_type" => "totp"}),
    do: {:totp, code}
end
