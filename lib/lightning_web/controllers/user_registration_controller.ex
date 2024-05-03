defmodule LightningWeb.UserRegistrationController do
  use LightningWeb, :controller

  alias Lightning.Accounts
  alias LightningWeb.UserAuth

  def new(conn, _params) do
    changeset = Accounts.change_user_registration()

    render(conn, "new.html", changeset: changeset)
  end

  def create(conn, %{"user" => user_params}) do
    case Accounts.register_user(user_params) do
      {:ok, user} ->
        conn
        |> put_flash(:info, "User created successfully.")
        |> UserAuth.log_in_user(user)
        |> UserAuth.redirect_with_return_to()

      {:error, %Ecto.Changeset{} = changeset} ->
        render(conn, "new.html", changeset: changeset)
    end
  end
end
