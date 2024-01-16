defmodule LightningWeb.UserAuth do
  @moduledoc """
  The UserAuth controller.
  """
  use LightningWeb, :verified_routes

  import Phoenix.Controller
  import Plug.Conn

  alias Lightning.Accounts
  alias Lightning.Accounts.UserToken
  alias LightningWeb.Router.Helpers, as: Routes

  # Make the remember me cookie valid for 60 days.
  # If you want bump or reduce this value, also change
  # the token expiry itself in UserToken.
  @max_age 60 * 60 * 24 * 60
  @remember_me_cookie "_lightning_web_user_remember_me"
  @remember_me_options [sign: true, max_age: @max_age, same_site: "Lax"]

  @totp_session :user_totp_pending

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
    sudo_token = get_session(conn, :sudo_token)
    sudo_token && Accounts.delete_sudo_session_token(sudo_token)
    live_socket_id = get_session(conn, :live_socket_id)

    live_socket_id &&
      LightningWeb.Endpoint.broadcast(live_socket_id, "disconnect", %{})

    conn
    |> renew_session()
    |> delete_resp_cookie(@remember_me_cookie)
    |> redirect(to: "/users/log_in")
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
  Re-Authenticates the user by using the sudo token
  """
  def reauth_sudo_mode(conn, _opts) do
    conn = ensure_sudo_token(conn)
    user = conn.assigns[:current_user]
    sudo_token = get_session(conn, :sudo_token)

    valid? =
      user && sudo_token &&
        Accounts.sudo_session_token_valid?(
          user,
          Base.decode64!(sudo_token)
        )

    assign(conn, :sudo_mode?, valid?)
  end

  defp ensure_sudo_token(conn) do
    conn = fetch_query_params(conn)

    if token = conn.query_params["sudo_token"],
      do: put_session(conn, :sudo_token, token),
      else: conn
  end

  defp update_last_used(token) do
    UserToken.token_and_context_query(token, "api")
    |> Lightning.Repo.one()
    |> UserToken.last_used_changeset()
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
            # |> put_flash(:error, "You must log in to access this page.")
            |> maybe_store_return_to()
            |> redirect(to: Routes.user_session_path(conn, :new))
            |> halt()
        end

      get_format(conn) == "html" && totp_pending?(conn) &&
          conn.path_info != ["users", "two-factor"] ->
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
  def require_sudo_user(conn, _opts) do
    if conn.assigns[:sudo_mode?] do
      conn
    else
      conn
      |> put_flash(
        :error,
        "You must verify yourself again in order to access this page."
      )
      |> maybe_store_return_to_without_sudo_token()
      |> redirect(to: ~p"/auth/confirm_access")
      |> halt()
    end
  end

  @doc """
  Require that the user has the `superuser` role
  """
  def require_superuser(conn, _opts) do
    case conn.assigns[:current_user].role do
      :superuser ->
        conn

      _ ->
        conn
        |> get_format()
        |> case do
          "json" ->
            conn
            |> put_status(:forbidden)
            |> put_view(LightningWeb.ErrorView)
            |> render(:"403")
            |> halt()

          _ ->
            conn
            |> put_flash(:nav, :no_access_no_back)
            |> redirect(to: signed_in_path(conn))
            |> halt()
        end
    end
  end

  @doc """
  Used for LiveView routes that require the user to be re-authenticated.
  """
  def on_mount(:ensure_sudo, _params, session, socket) do
    socket = mount_sudo_mode(session, socket)

    if socket.assigns.sudo_mode? do
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

  defp mount_sudo_mode(session, socket) do
    case session do
      %{"sudo_token" => sudo_token} ->
        user = socket.assigns[:current_user]
        decoded_token = Base.decode64!(sudo_token)

        Phoenix.Component.assign_new(socket, :sudo_mode?, fn ->
          user && Accounts.sudo_session_token_valid?(user, decoded_token)
        end)

      _other ->
        Phoenix.Component.assign_new(socket, :sudo_mode?, fn ->
          nil
        end)
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

  defp maybe_store_return_to_without_sudo_token(conn) do
    conn = conn |> maybe_store_return_to() |> fetch_query_params()
    return_to = get_session(conn, :user_return_to)

    if return_to && conn.query_params["sudo_token"] do
      uri = URI.new!(return_to)
      updated_query = Map.drop(conn.query_params, ["sudo_token"])

      uri = %{uri | query: Plug.Conn.Query.encode(updated_query)}

      path = URI.to_string(uri)

      put_session(conn, :user_return_to, path)
    else
      conn
    end
  end

  defp signed_in_path(_conn), do: "/"
end
