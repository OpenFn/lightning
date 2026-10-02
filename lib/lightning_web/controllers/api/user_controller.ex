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

  `GET /api/users` is paginated and filters by `?email=` without regard to
  case.
  """
  use LightningWeb, :controller

  import LightningWeb.Plugs.AccessTokenAuth, only: [require_scope: 2]

  alias Lightning.Accounts
  alias Lightning.Accounts.User

  action_fallback LightningWeb.FallbackController

  plug :require_scope, "users:read" when action in [:index, :show]
  plug :require_scope, "users:write" when action in [:create, :update]

  def index(conn, params) do
    render(conn, "index.json", page: Accounts.paginate_users(params), conn: conn)
  end

  def show(conn, %{"id" => id}) do
    with {:ok, user} <- fetch_user(id) do
      render(conn, "show.json", user: user, conn: conn)
    end
  end

  def update(conn, %{"id" => id} = params) do
    with {:ok, user} <- fetch_user(id),
         {:ok, user} <-
           Accounts.update_user_as_service_account(
             user,
             params,
             conn.assigns.service_account
           ) do
      render(conn, "show.json", user: user, conn: conn)
    end
  end

  def create(conn, params) do
    case Accounts.create_user_as_service_account(
           params,
           conn.assigns.service_account
         ) do
      {:ok, user} ->
        conn
        |> put_status(:created)
        |> render("show.json", user: user, conn: conn)

      {:error, :email_taken, user} ->
        conn
        |> put_status(:conflict)
        |> render("show.json", user: user, conn: conn)

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  defp fetch_user(id) do
    with {:ok, id} <- Ecto.UUID.cast(id),
         %User{} = user <- Accounts.get_user(id) do
      {:ok, user}
    else
      _ -> {:error, :not_found}
    end
  end
end
