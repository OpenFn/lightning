defmodule LightningWeb.API.UserController do
  @moduledoc """
  The users resource, for service accounts only.

  `POST /api/users` takes a flat object of `email`, `password`, `first_name`,
  `last_name`, `role` (`user` or `superuser`) and `confirmed`, and refuses any
  other key with a 422 `unknown_key` entry at that key, alongside every other
  error in the body. It answers 201 with the new user. An email already taken
  in any case is a `taken` entry at `#/email`, which names nothing about the
  user who holds it.

  `PATCH /api/users/:id` takes any of `first_name`, `last_name`, `role`,
  `password` and `confirmed`, with the same rules as a create, and refuses any
  other key the same way, `email` included, since the email can't be changed.
  It answers 200 with the user rendered as a 201 renders one. `confirmed` only
  ever confirms.

  Either answers 400 `malformed` to a body that isn't a JSON object.

  `GET /api/users` is paginated, at most 100 a page, and filters by `?email=`
  without regard to case. An `email` that isn't a string answers 400
  `invalid_parameter`.
  """
  use LightningWeb, :controller

  alias Lightning.Accounts
  alias Lightning.Accounts.User
  alias LightningWeb.API.Errors
  alias LightningWeb.API.FallbackController
  alias LightningWeb.API.Request
  alias LightningWeb.Plugs.AuthorizeAction

  action_fallback FallbackController

  @create_fields ~w(email password first_name last_name role confirmed)a
  @update_fields ~w(first_name last_name role password confirmed)a
  @create_keys Enum.map(@create_fields, &Atom.to_string/1)
  @update_keys Enum.map(@update_fields, &Atom.to_string/1)

  plug AuthorizeAction,
       {:users, :read_users}
       when action in [:index, :show]

  plug AuthorizeAction,
       {:users, :write_users}
       when action in [:create, :update]

  def index(conn, params) do
    with {:ok, page} <-
           params |> Accounts.paginate_users() |> Errors.refuse_parameters() do
      render(conn, "index.json",
        page: page,
        filters: applied_filters(params),
        conn: conn
      )
    end
  end

  def show(conn, %{"id" => id}) do
    with {:ok, user} <- fetch_user(id) do
      render(conn, "show.json", user: user, conn: conn)
    end
  end

  def update(conn, %{"id" => id}) do
    body = conn.body_params
    attrs = Map.take(body, @update_keys)

    with {:ok, user} <- fetch_user(id),
         :ok <- Request.check_object(body),
         :ok <-
           refuse_unknown_keys(body, @update_fields, fn ->
             User.details_changeset(user, attrs)
           end),
         {:ok, user} <-
           Accounts.update_user(user, attrs, conn.assigns.current_resource) do
      render(conn, "show.json", user: user, conn: conn)
    end
  end

  def create(conn, _params) do
    body = conn.body_params
    attrs = Map.take(body, @create_keys)

    with :ok <- Request.check_object(body),
         :ok <-
           refuse_unknown_keys(body, @create_fields, fn ->
             Accounts.change_user(%User{}, attrs)
           end),
         {:ok, user} <-
           Accounts.create_user(attrs, conn.assigns.current_resource) do
      conn
      |> put_status(:created)
      |> render("show.json", user: user, conn: conn)
    end
  end

  # An unknown key refuses the body together with every error its changeset
  # holds.
  defp refuse_unknown_keys(body, accepted, build_changeset) do
    case Request.unknown_keys(body, [], accepted) do
      [] ->
        :ok

      unknown ->
        Errors.refuse(unknown ++ Errors.from_changeset(build_changeset.()))
    end
  end

  # Reached only once `paginate_users` has accepted the email as a string.
  defp applied_filters(%{"email" => email}), do: %{email: email}
  defp applied_filters(_params), do: %{}

  defp fetch_user(id) do
    with {:ok, id} <- Request.path_id(id),
         %User{} = user <- Accounts.get_user(id) do
      {:ok, user}
    else
      nil -> {:error, :not_found}
      error -> error
    end
  end
end
