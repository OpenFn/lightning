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
        maybe_create_initial_project(user)

        conn
        |> put_flash(:info, "User created successfully.")
        |> UserAuth.log_in_user(user)
        |> UserAuth.redirect_with_return_to()

      {:error, %Ecto.Changeset{} = changeset} ->
        render(conn, "new.html", changeset: changeset)
    end
  end

  defp maybe_create_initial_project(user) do
    if Lightning.Config.check_flag?(:init_project_for_new_user) do
      project_name =
        "#{String.downcase(user.first_name)}-demo" |> String.replace(" ", "-")

      Lightning.SetupUtils.create_starter_project(
        project_name,
        [%{user_id: user.id, role: :owner}]
      )
    end
  end
end
