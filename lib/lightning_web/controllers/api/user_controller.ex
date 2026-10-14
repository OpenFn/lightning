defmodule LightningWeb.API.UserController do
  @moduledoc """
  The users resource, for service accounts only.

  `POST /api/users` takes a flat object of `email`, `password`, `first_name`,
  `last_name`, `role` (`user` or `superuser`) and `confirmed`, and ignores any
  other key. It answers 201 with the new user, or 409 with the existing user,
  rendered the same way, when the email is already taken in any case.

  `PATCH /api/users/:id` takes any of `first_name`, `last_name`, `role`,
  `password` and `confirmed`, with the same rules as a create, and answers 200
  with the user rendered as a 201 renders one. The email can't be changed, and
  `confirmed` only ever confirms.

  `GET /api/users` is paginated, at most 100 a page, and filters by `?email=`
  without regard to case. An `email` that isn't a string answers 422.
  """
  use LightningWeb, :controller

  alias Lightning.Accounts
  alias Lightning.Accounts.User
  alias Lightning.Policies.Permissions
  alias LightningWeb.Plugs.AuthorizeAction

  action_fallback LightningWeb.FallbackController

  @create_fields ~w(email password first_name last_name role confirmed)
  @update_fields ~w(first_name last_name role password confirmed)

  plug AuthorizeAction, {:users, :read_users} when action in [:index, :show]
  plug AuthorizeAction, {:users, :write_users} when action in [:create, :update]

  def index(conn, params) do
    with :ok <- permit(conn, :read_users),
         {:ok, page} <- Accounts.paginate_users(params) do
      render(conn, "index.json", page: page, conn: conn)
    end
  end

  def show(conn, %{"id" => id}) do
    with :ok <- permit(conn, :read_users),
         {:ok, user} <- fetch_user(id) do
      render(conn, "show.json", user: user, conn: conn)
    end
  end

  def update(conn, %{"id" => id} = params) do
    with :ok <- permit(conn, :write_users),
         {:ok, user} <- fetch_user(id),
         {:ok, user} <-
           Accounts.update_user(
             user,
             Map.take(params, @update_fields),
             conn.assigns.current_resource
           ) do
      render(conn, "show.json", user: user, conn: conn)
    end
  end

  def create(conn, params) do
    with :ok <- permit(conn, :write_users) do
      create_user(conn, params)
    end
  end

  defp create_user(conn, params) do
    case Accounts.create_user(
           Map.take(params, @create_fields),
           conn.assigns.current_resource
         ) do
      {:ok, user} ->
        conn
        |> put_status(:created)
        |> render("show.json", user: user, conn: conn)

      {:error, changeset} ->
        case holder_of_taken_email(changeset) do
          %User{} = user ->
            conn
            |> put_status(:conflict)
            |> render("show.json", user: user, conn: conn)

          nil ->
            {:error, changeset}
        end
    end
  end

  defp holder_of_taken_email(changeset) do
    taken? =
      changeset.errors
      |> Keyword.get_values(:email)
      |> Enum.any?(fn {_message, opts} ->
        opts[:validation] == :unsafe_unique or opts[:constraint] == :unique
      end)

    if taken?,
      do: Accounts.get_user_by_email(Ecto.Changeset.get_field(changeset, :email))
  end

  defp permit(conn, action),
    do: Permissions.permit(:users, action, conn.assigns.scope, nil)

  defp fetch_user(id) do
    with {:ok, id} <- Ecto.UUID.cast(id),
         %User{} = user <- Accounts.get_user(id) do
      {:ok, user}
    else
      _ -> {:error, :not_found}
    end
  end
end
