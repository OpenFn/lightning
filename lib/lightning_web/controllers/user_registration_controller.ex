defmodule LightningWeb.UserRegistrationController do
  use LightningWeb, :controller

  alias Lightning.Accounts
  alias LightningWeb.ChangesetJSON
  alias LightningWeb.UserAuth

  def new(conn, _params) do
    changeset = Accounts.change_user_registration()
    render(conn, "new.html", changeset: changeset)
  end

  def create(conn, %{"user" => user_params}) do
    conn
    |> register_user(user_params)
    |> handle_register_resp(conn)
  end

  defp handle_register_resp({:ok, user}, conn) do
    case get_format(conn) do
      "json" ->
        conn
        |> put_status(200)
        |> json(%{data: %{id: user.id}})

      _html ->
        conn
        |> put_flash(:info, "User created successfully.")
        |> UserAuth.log_in_user(user)
        |> UserAuth.redirect_with_return_to()
    end
  end

  defp handle_register_resp({:error, %Ecto.Changeset{} = changeset}, conn) do
    case get_format(conn) do
      "json" ->
        conn
        |> put_status(400)
        |> json(ChangesetJSON.error(%{changeset: changeset}))

      _html ->
        render(conn, "new.html", changeset: changeset)
    end
  end

  defp register_user(conn, params) do
    with {:ok, user} <- Accounts.register_user(params) do
      {:ok, _} =
        Accounts.deliver_user_confirmation_instructions(
          user,
          &Routes.user_confirmation_url(conn, :edit, &1)
        )

      if Application.get_env(:lightning, :init_project_for_new_user) do
        create_initial_project(user)
      end

      {:ok, user}
    end
  end

  defp create_initial_project(%Lightning.Accounts.User{
         id: user_id,
         first_name: first_name
       }) do
    project_name =
      "#{String.downcase(first_name)}-demo" |> String.replace(" ", "-")

    Lightning.SetupUtils.create_starter_project(
      project_name,
      [%{user_id: user_id, role: :owner}]
    )
  end
end
