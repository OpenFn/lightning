defmodule LightningWeb.API.SessionHelpers do
  @moduledoc """
  Conns that call the API with a session token, the way Lightning's own app
  does: the person's session cookie, a request from Lightning's own page, and
  the session's CSRF token in `x-csrf-token`.

      conn = session_conn(build_conn(), user)
      conn = session_conn(build_conn(), user, stepped_up: true)
      conn |> without_csrf() |> put(~p"/api/...", body)
      conn = from_own_page(build_conn())    # no session yet, to sign in

  Options:

    * `:stepped_up` - `true` to step the session up, as entering a password or
      MFA code does, for the next five minutes.
    * `:mfa_pending` - `true` for a session signed in with a password and still
      waiting for its MFA code.
    * `:origin` - `:same` (the default) sends `Sec-Fetch-Site: same-origin`;
      `:cross` sends `Sec-Fetch-Site: cross-site`; `:none` sends neither it nor
      `Origin`.
    * `:csrf` - `false` to leave out the `x-csrf-token` header. The session
      still holds its CSRF state, so `csrf_token/1` can add it later.

  The conn also accepts JSON and sends it, as the app does.
  """
  import Plug.Conn

  alias Lightning.Accounts
  alias Lightning.Accounts.User

  @csrf_header "x-csrf-token"

  @spec session_conn(Plug.Conn.t(), User.t(), keyword()) :: Plug.Conn.t()
  def session_conn(conn, %User{} = user, opts \\ []) do
    {masked, state} = new_csrf_token()

    conn
    |> Phoenix.ConnTest.init_test_session(%{})
    |> put_session(:user_token, Accounts.generate_user_session_token(user))
    |> put_session("_csrf_token", state)
    |> put_private(:session_helpers_csrf_token, masked)
    |> put_req_header("accept", "application/json")
    |> put_req_header("content-type", "application/json")
    |> put_origin(Keyword.get(opts, :origin, :same))
    |> then(&if(Keyword.get(opts, :csrf, true), do: csrf_token(&1), else: &1))
    |> then(&if(opts[:stepped_up], do: step_up(&1, user), else: &1))
    |> then(
      &if(opts[:mfa_pending],
        do: put_session(&1, :user_totp_pending, true),
        else: &1
      )
    )
  end

  @doc """
  A request from Lightning's own page with no session yet, accepting and
  sending JSON, as the app signs in.
  """
  @spec from_own_page(Plug.Conn.t()) :: Plug.Conn.t()
  def from_own_page(conn) do
    conn
    |> put_req_header("accept", "application/json")
    |> put_req_header("content-type", "application/json")
    |> put_origin(:same)
  end

  @doc "Adds the session's CSRF token as `x-csrf-token`."
  @spec csrf_token(Plug.Conn.t()) :: Plug.Conn.t()
  def csrf_token(conn),
    do:
      put_req_header(conn, @csrf_header, conn.private.session_helpers_csrf_token)

  @doc "Removes the `x-csrf-token` header."
  @spec without_csrf(Plug.Conn.t()) :: Plug.Conn.t()
  def without_csrf(conn), do: delete_req_header(conn, @csrf_header)

  @doc """
  Steps the session up for `user` for five minutes, or, given
  `seconds_ago`, as if it had been stepped up that long ago.
  """
  @spec step_up(Plug.Conn.t(), User.t(), non_neg_integer()) :: Plug.Conn.t()
  def step_up(conn, %User{} = user, seconds_ago \\ 0) do
    token = Accounts.generate_sudo_session_token(user)

    if seconds_ago > 0 do
      inserted_at =
        DateTime.utc_now()
        |> DateTime.add(-seconds_ago)
        |> DateTime.truncate(:second)

      Lightning.Repo.update_all(
        Accounts.UserToken.token_and_context_query(token, "sudo_session"),
        set: [inserted_at: inserted_at]
      )
    end

    put_session(conn, :sudo_token, Base.encode64(token))
  end

  defp put_origin(conn, :same),
    do: put_req_header(conn, "sec-fetch-site", "same-origin")

  defp put_origin(conn, :cross),
    do: put_req_header(conn, "sec-fetch-site", "cross-site")

  defp put_origin(conn, :none), do: conn

  # Plug keeps the CSRF state in the process dictionary, and tests dispatch
  # requests in the test's own process, so it is cleared again here.
  defp new_csrf_token do
    Plug.CSRFProtection.load_state(nil, nil)
    Process.delete(:plug_masked_csrf_token)
    masked = Plug.CSRFProtection.get_csrf_token()
    state = Plug.CSRFProtection.dump_state()

    for key <- [
          :plug_masked_csrf_token,
          :plug_unmasked_csrf_token,
          :plug_csrf_token_per_host
        ],
        do: Process.delete(key)

    {masked, state}
  end
end
