defmodule LightningWeb.UserRegistrationController do
  use LightningWeb, :controller

  alias Lightning.Accounts
  alias LightningWeb.UserAuth

  def new(conn, _params) do
    changeset = Accounts.change_user_registration()
    render(conn, "new.html", changeset: changeset)
  end

  defp create_initial_project(%Lightning.Accounts.User{
         id: user_id,
         first_name: first_name
       }) do
    project_name =
      "#{String.downcase(first_name)}-demo" |> String.replace(" ", "-")

    Lightning.SetupUtils.create_starter_project(
      project_name,
      [%{user_id: user_id, role: :admin}]
    )
  end

  def create(conn, %{"user" => user_params}) do
    case Accounts.register_user(user_params) do
      {:ok, user} ->
        {:ok, _} =
          Accounts.deliver_user_confirmation_instructions(
            user,
            &Routes.user_confirmation_url(conn, :edit, &1)
          )

        if Application.get_env(:lightning, :init_project_for_new_user) do
          create_initial_project(user)
        end

        conn
        |> put_flash(:info, "User created successfully.")
        |> UserAuth.log_in_user(user)
        |> UserAuth.redirect_with_return_to()

      {:error, %Ecto.Changeset{} = changeset} ->
        render(conn, "new.html", changeset: changeset)
    end
  end
end
