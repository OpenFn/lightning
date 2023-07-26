defmodule LightningWeb.UserAuth do
  @moduledoc """
  The UserAuth controller.
  """

  import Plug.Conn
  import Phoenix.Controller
  use LightningWeb, :verified_routes

  alias Lightning.Accounts
  alias LightningWeb.Router.Helpers, as: Routes

  # Make the remember me cookie valid for 60 days.
  # If you want bump or reduce this value, also change
  # the token expiry itself in UserToken.
  @max_age 60 * 60 * 24 * 60
  @remember_me_cookie "_lightning_web_user_remember_me"
  @remember_me_options [sign: true, max_age: @max_age, same_site: "Lax"]

  @totp_session :user_totp_pending
  @reauthenticated_cookie "_lightning_reauthenticated_key"
  # max age should be short, ideally 5 minutes
  @reauthenticated_options [sign: true, max_age: 60 * 5, same_site: "Strict"]

  @doc """
  Logs the user in by creating a new session token.
  """
  def log_in_user(conn, user) do
    token = Accounts.generate_user_session_token(user)
    new_session(conn, token)
  end

  @doc """
  Assigns the token to a new session.

  It renews the session ID and clears the whole session
  to avoid fixation attacks. See the renew_session
  function to customize this behaviour.

  It also sets a `:live_socket_id` key in the session,
  so LiveView sessions are identified and automatically
  disconnected on log out. The line can be safely removed
  if you are not using LiveView.
  """
  def new_session(conn, token) do
    conn
    |> renew_session()
    |> put_session(:user_token, token)
    |> put_session(:live_socket_id, "users_sessions:#{Base.url_encode64(token)}")
  end

  @doc """
  Returns to or redirects to the dashboard and potentially set remember_me token.
  """
  def redirect_with_return_to(conn, params \\ %{}) do
    user_return_to = get_session(conn, :user_return_to)

    conn
    |> maybe_write_remember_me_cookie(params)
    |> delete_session(:user_return_to)
    |> redirect(to: user_return_to || signed_in_path(conn))
  end

  defp maybe_write_remember_me_cookie(conn, %{"remember_me" => "true"}) do
    token = get_session(conn, :user_token)
    put_resp_cookie(conn, @remember_me_cookie, token, @remember_me_options)
  end

  defp maybe_write_remember_me_cookie(conn, _params) do
    conn
  end

  # This function renews the session ID and erases the whole
  # session to avoid fixation attacks. If there is any data
  # in the session you may want to preserve after log in/log out,
  # you must explicitly fetch the session data before clearing
  # and then immediately set it after clearing, for example:
  #
  #     defp renew_session(conn) do
  #       preferred_locale = get_session(conn, :preferred_locale)
  #
  #       conn
  #       |> configure_session(renew: true)
  #       |> clear_session()
  #       |> put_session(:preferred_locale, preferred_locale)
  #     end
  #
  defp renew_session(conn) do
    user_return_to = get_session(conn, :user_return_to)

    conn
    |> configure_session(renew: true)
    |> clear_session()
    |> put_session(:user_return_to, user_return_to)
  end

  @doc """
  Logs the user out.

  It clears all session data for safety. See renew_session.
  """
  def log_out_user(conn) do
    user_token = get_session(conn, :user_token)
    user_token && Accounts.delete_session_token(user_token)
    reauthenticate_token = fetch_cookies(conn, signed: [@reauthenticated_cookie])
    reauthenticate_token && Accounts.delete_two_factor_session_token(user_token)

    if live_socket_id = get_session(conn, :live_socket_id) do
      LightningWeb.Endpoint.broadcast(live_socket_id, "disconnect", %{})
    end

    conn
    |> renew_session()
    |> delete_resp_cookie(@remember_me_cookie)
    |> delete_resp_cookie(@reauthenticated_cookie)
    |> redirect(to: "/")
  end

  @doc """
  Authenticates the user by looking into the session
  and remember me token.
  """
  def fetch_current_user(conn, _opts) do
    {user_token, conn} = ensure_user_token(conn)
    user = user_token && Accounts.get_user_by_session_token(user_token)
    assign(conn, :current_user, user)
  end

  defp ensure_user_token(conn) do
    if user_token = get_session(conn, :user_token) do
      {user_token, conn}
    else
      conn = fetch_cookies(conn, signed: [@remember_me_cookie])

      if user_token = conn.cookies[@remember_me_cookie] do
        {user_token, put_session(conn, :user_token, user_token)}
      else
        {nil, conn}
      end
    end
  end

  @doc """
  Re-Authenticates the user by looking into the cookies or query params
  """
  def reauthenticate_user(conn, _opts) do
    {user_token, conn} = ensure_two_factor_token(conn)
    user = conn.assigns.current_user

    valid? =
      user && user_token &&
        Accounts.two_factor_session_token_valid?(user, user_token)

    assign(conn, :user_reauthenticated?, valid?)
  end

  defp ensure_two_factor_token(conn) do
    conn = fetch_query_params(conn)

    if token = conn.query_params["token"] do
      user_token = Base.decode32!(token)
      {user_token, write_reauthentication_cookie(conn, user_token)}
    else
      conn = fetch_cookies(conn, signed: [@reauthenticated_cookie])

      if user_token = conn.cookies[@reauthenticated_cookie] do
        {user_token, conn}
      else
        {nil, conn}
      end
    end
  end

  defp write_reauthentication_cookie(conn, token) do
    conn
    |> put_resp_cookie(
      @reauthenticated_cookie,
      token,
      @reauthenticated_options
    )
  end

  defp update_last_used(token) do
    Lightning.Accounts.UserToken.token_and_context_query(token, "api")
    |> Lightning.Repo.one()
    |> Lightning.Accounts.UserToken.last_used_changeset()
    |> Lightning.Repo.update!()
  end

  def authenticate_bearer(conn, _opts) do
    with {:ok, bearer_token} <- get_bearer(conn),
         user when not is_nil(user) <-
           Accounts.get_user_by_api_token(bearer_token) do
      update_last_used(bearer_token)
      assign(conn, :current_user, user)
    else
      _ -> conn
    end
  end

  defp get_bearer(conn) do
    conn
    |> get_req_header("authorization")
    |> case do
      ["Bearer " <> bearer_token] -> {:ok, bearer_token}
      _ -> {:error, "Bearer Token not found"}
    end
  end

  @doc """
  Used for routes that require the user to not be authenticated.
  """
  def redirect_if_user_is_authenticated(conn, _opts) do
    if conn.assigns[:current_user] do
      conn
      |> redirect(to: signed_in_path(conn))
      |> halt()
    else
      conn
    end
  end

  @doc """
  Used for routes that require the user to be authenticated.

  If you want to enforce the user email is confirmed before
  they use the application at all, here would be a good place.
  """
  def require_authenticated_user(conn, _opts) do
    cond do
      is_nil(conn.assigns[:current_user]) ->
        conn
        |> get_format()
        |> case do
          "json" ->
            conn
            |> put_status(:unauthorized)
            |> put_view(LightningWeb.ErrorView)
            |> render(:"401")
            |> halt()

          _ ->
            conn
            |> put_flash(:error, "You must log in to access this page.")
            |> maybe_store_return_to()
            |> redirect(to: Routes.user_session_path(conn, :new))
            |> halt()
        end

      get_format(conn) == "html" && totp_pending?(conn) &&
          conn.path_info != ["users", "two-factor", "app"] ->
        conn
        |> redirect(to: Routes.user_totp_path(conn, :new))
        |> halt()

      true ->
        conn
    end
  end

  @doc """
  Used for routes that require the user to be re-authenticated.
  """
  def require_reauthenticated_user(conn, _opts) do
    if is_nil(conn.assigns[:user_reauthenticated?]) do
      conn
      |> put_flash(
        :error,
        "You must verify yourself again in order to access this page."
      )
      |> maybe_store_return_to()
      |> redirect(to: ~p"/auth/confirm_access")
      |> halt()
    else
      conn
    end
  end

  @doc """
  Used for LiveView routes that require the user to be re-authenticated.
  """
  def on_mount(:ensure_reauthenticated, _params, session, socket) do
    socket = mount_user_reauthentication(session, socket)

    if socket.assigns.current_user do
      {:cont, socket}
    else
      socket =
        socket
        |> Phoenix.LiveView.put_flash(
          :error,
          "You must verify yourself again in order to access this page."
        )
        |> Phoenix.LiveView.redirect(to: ~p"/auth/confirm_access")

      {:halt, socket}
    end
  end

  defp mount_user_reauthentication(session, socket) do
    with %{} = user <- socket.assigns.current_user,
         %{"two_factor_token" => user_token} <- session do
      Phoenix.Component.assign_new(socket, :user_reauthenticated?, fn ->
        Accounts.two_factor_session_token_valid?(user, user_token)
      end)
    else
      _other ->
        Phoenix.Component.assign_new(socket, :user_reauthenticated?, fn ->
          nil
        end)
    end
  end

  @doc """
  Fetches the two factor token to be used in LiveView sessions
  """
  def reauthentication_session(conn) do
    {user_token, conn} = ensure_two_factor_token(conn)

    if user_token do
      %{"two_factor_token" => user_token}
    else
      %{}
    end
  end

  def mark_totp_pending(conn) do
    put_session(conn, @totp_session, true)
  end

  def totp_pending?(conn) do
    get_session(conn, @totp_session)
  end

  def totp_validated(conn) do
    delete_session(conn, @totp_session)
  end

  defp maybe_store_return_to(%{method: "GET"} = conn) do
    put_session(conn, :user_return_to, current_path(conn))
  end

  defp maybe_store_return_to(conn), do: conn

  defp signed_in_path(_conn), do: "/"
end
