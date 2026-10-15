defmodule LightningWeb.API.UserController do
  @moduledoc """
  The users resource, for service accounts only.

  `POST /api/users` takes a flat object of `email`, `password`, `first_name`,
  `last_name`, `role` (`user` or `superuser`) and `confirmed`, and ignores any
  other key. It answers 201 with the new user. When the email is already taken
  in any case, it answers 409 `taken` with the existing user's id in
  `existing`, and nothing else of that user (error-format spec §9.9).

  `PATCH /api/users/:id` takes any of `first_name`, `last_name`, `role`,
  `password` and `confirmed`, with the same rules as a create, and answers 200
  with the user rendered as a 201 renders one. The email can't be changed, and
  `confirmed` only ever confirms.

  `GET /api/users` is paginated, at most 100 a page, and filters by `?email=`
  without regard to case. An `email` that isn't a string answers 400
  `invalid_parameter`.
  """
  use LightningWeb, :controller

  alias Ecto.Changeset
  alias Lightning.Accounts
  alias Lightning.Accounts.User
  alias Lightning.Policies.Permissions
  alias LightningWeb.API.Errors
  alias LightningWeb.API.FallbackController
  alias LightningWeb.API.Problem
  alias LightningWeb.Plugs.AuthorizeAction

  action_fallback FallbackController

  @create_fields ~w(email password first_name last_name role confirmed)
  @update_fields ~w(first_name last_name role password confirmed)

  plug AuthorizeAction,
       {:users, :read_users, fallback: FallbackController}
       when action in [:index, :show]

  plug AuthorizeAction,
       {:users, :write_users, fallback: FallbackController}
       when action in [:create, :update]

  def index(conn, params) do
    with :ok <- permit(conn, :read_users) do
      case Accounts.paginate_users(params) do
        {:ok, page} -> render(conn, "index.json", page: page, conn: conn)
        {:error, changeset} -> {:error, Errors.parameters(changeset)}
      end
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
      case Accounts.create_user(
             Map.take(params, @create_fields),
             conn.assigns.current_resource
           ) do
        {:ok, user} ->
          conn
          |> put_status(:created)
          |> render("show.json", user: user, conn: conn)

        {:error, changeset} ->
          {:error, creation_problem(changeset)}
      end
    end
  end

  # A create's only unique field is the email, so a `taken` problem means a
  # user holds it, unless that user was deleted since.
  defp creation_problem(changeset) do
    case Errors.problem(changeset) do
      %Problem{code: :taken} = problem ->
        case Accounts.get_user_by_email(Changeset.get_field(changeset, :email)) do
          %User{id: id} -> %{problem | extensions: %{existing: %{id: id}}}
          nil -> problem
        end

      problem ->
        problem
    end
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
