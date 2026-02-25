defmodule LightningWeb.UserConfirmationController do
  use LightningWeb, :controller

  alias Lightning.Accounts
  alias Lightning.Accounts.User

  def new(conn, _params) do
    render(conn, "new.html")
  end

  def create(conn, %{"user" => %{"email" => email}}) do
    if user = Accounts.get_user_by_email(email) do
      Accounts.deliver_user_confirmation_instructions(user)
    end

    conn
    |> put_flash(
      :info,
      "If your email is in our system and it has not been confirmed yet, " <>
        "you will receive an email with instructions shortly."
    )
    |> redirect(to: "/projects")
  end

  def edit(conn, %{"token" => token}) do
    case Accounts.get_user_by_confirmation_token(token) do
      %User{id: id} when id == conn.assigns.current_user.id ->
        render(conn, "edit.html", token: token)

      %User{} ->
        conn
        |> put_flash(
          :error,
          "You are logged in as a different user. Please log out to confirm this account."
        )
        |> redirect(to: "/projects")

      nil ->
        conn
        |> put_flash(
          :error,
          "User confirmation link is invalid or it has expired."
        )
        |> redirect(to: "/projects")
    end
  end

  def confirm_email(conn, %{"token" => token}) do
    case Accounts.update_user_email(conn.assigns.current_user, token) do
      {:ok, _} ->
        conn
        |> put_flash(:info, "Email changed successfully.")
        |> redirect(to: "/projects")

      :error ->
        conn
        |> put_flash(
          :error,
          "Email change link is invalid or it has expired."
        )
        |> redirect(to: "/projects")
    end
  end

  def send_email(
        %{assigns: %{current_user: %{confirmed_at: nil}}} = conn,
        _params
      ) do
    Lightning.Accounts.remind_account_confirmation(conn.assigns.current_user)

    conn
    |> put_flash(:info, "Confirmation email sent successfully")
    |> redirect(to: get_referer(conn))
  end

  def send_email(conn, _params) do
    redirect(conn, to: get_referer(conn))
  end

  defp get_referer(conn) do
    conn
    |> Plug.Conn.get_req_header("referer")
    |> List.first()
    |> case do
      nil -> "/projects"
      referer -> URI.parse(referer) |> Map.get(:path)
    end
  end

  def update(conn, %{"token" => token}) do
    case Accounts.get_user_by_confirmation_token(token) do
      %User{id: id} when id == conn.assigns.current_user.id ->
        case Accounts.confirm_user(token) do
          {:ok, _} ->
            conn
            |> put_flash(:info, "User confirmed successfully.")
            |> redirect(to: "/projects")

          :error ->
            conn
            |> put_flash(
              :error,
              "User confirmation link is invalid or it has expired."
            )
            |> redirect(to: "/projects")
        end

      %User{} ->
        conn
        |> put_flash(
          :error,
          "You are logged in as a different user. Please log out to confirm this account."
        )
        |> redirect(to: "/projects")

      nil ->
        # If there is a current user and the account was already confirmed,
        # then odds are that the confirmation link was already visited, either
        # by some automation or by the user themselves, so we redirect without
        # a warning message.
        if conn.assigns.current_user.confirmed_at do
          redirect(conn, to: "/projects")
        else
          conn
          |> put_flash(
            :error,
            "User confirmation link is invalid or it has expired."
          )
          |> redirect(to: "/projects")
        end
    end
  end
end
