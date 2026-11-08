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

  A person may also `PATCH` their own id, with a personal access token or a
  session token, and change their own `first_name`, `last_name` and
  `contact_preference` (`critical` or `any`). With a session token stepped up,
  they may also send `password`, which ends their other sessions and revokes
  their personal access tokens, and `email`, which sends a link to the new
  address and changes nothing until it is followed. Sending either on any
  other token answers 403 `forbidden`, or `step_up_required` on a session that
  hasn't stepped up. Any other key, `role` included, is refused as
  `unknown_key` the same way. Any other id answers them 403 `forbidden` before
  it is looked up, so the answer says nothing about whether it names a user.

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
  @own_fields ~w(first_name last_name contact_preference password email)a
  @sign_in_keys ~w(password email)
  @create_keys Enum.map(@create_fields, &Atom.to_string/1)
  @update_keys Enum.map(@update_fields, &Atom.to_string/1)
  @own_keys Enum.map(@own_fields, &Atom.to_string/1)

  plug AuthorizeAction,
       {:users, :read_users}
       when action in [:index, :show]

  plug AuthorizeAction,
       {:users, :write_users}
       when action == :create

  plug :authorize_update when action == :update

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

  def show(conn, _params) do
    with {:ok, user} <- fetch_user(Request.param(conn, "id")) do
      render(conn, "show.json", user: user, conn: conn)
    end
  end

  def update(conn, _params) do
    if own_account?(conn), do: update_own(conn), else: update_any(conn)
  end

  defp update_own(conn) do
    body = conn.body_params
    attrs = Map.take(body, @own_keys)
    user = conn.assigns.current_resource

    with :ok <- Request.check_object(body),
         :ok <-
           refuse_unknown_keys(body, @own_fields, fn ->
             User.own_account_changeset(user, attrs)
           end),
         {:ok, user} <-
           Accounts.update_own_account(user, attrs,
             keep_session: session_token(conn)
           ) do
      render(conn, "show.json", user: user, conn: conn)
    end
  end

  defp update_any(conn) do
    body = conn.body_params
    attrs = Map.take(body, @update_keys)

    with {:ok, user} <- fetch_user(Request.param(conn, "id")),
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

  # A person naming their own id changes their own account, and needs a
  # stepped-up session to send the email or password they sign in with. Anyone
  # else needs the service account's `users:write`, which refuses a person
  # whatever the id names.
  defp authorize_update(conn, _opts) do
    permission =
      cond do
        not own_account?(conn) -> {:users, :write_users}
        sends_sign_in?(conn.body_params) -> {:users, :update_own_sign_in}
        true -> {:users, :update_own_account}
      end

    AuthorizeAction.call(conn, AuthorizeAction.init(permission))
  end

  defp sends_sign_in?(body),
    do: Enum.any?(@sign_in_keys, &Map.has_key?(body, &1))

  # The session that made the change, which a new password keeps signed in.
  defp session_token(%{assigns: %{token_kind: :session}} = conn) do
    {token, _conn} = LightningWeb.UserAuth.session_user_token(conn)
    token
  end

  defp session_token(_conn), do: nil

  defp own_account?(%{assigns: %{current_resource: %User{id: id}}} = conn),
    do: match?({_location, ^id}, Request.param(conn, "id"))

  defp own_account?(_conn), do: false

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
    with {:ok, id} <- Request.id(id),
         %User{} = user <- Accounts.get_user(id) do
      {:ok, user}
    else
      nil -> {:error, :not_found}
      error -> error
    end
  end
end
