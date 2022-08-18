defmodule LightningWeb.UserSessionController do
  use LightningWeb, :controller

  alias Lightning.Accounts
  alias LightningWeb.UserAuth
  alias Lightning.Accounts.User

  def new(conn, _params) do
    render(conn, "new.html", error_message: nil)
  end

  def create(conn, %{"user" => user_params}) do
    %{"email" => email, "password" => password} = user_params

    Accounts.get_user_by_email_and_password(email, password)
    |> case do
      %User{disabled: true} ->
        render(conn, "new.html", error_message: "This user account is disabled")

      %User{scheduled_deletion: _x} ->
        render(conn, "new.html",
          error_message: "This user account is scheduled for deletion"
        )

      %User{} = user ->
        UserAuth.log_in_user(conn, user, user_params)

      _ ->
        render(conn, "new.html", error_message: "Invalid email or password")
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
    end
  end

  def delete(conn, _params) do
    conn
    |> put_flash(:info, "Logged out successfully.")
    |> UserAuth.log_out_user()
  end
end
