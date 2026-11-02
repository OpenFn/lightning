defmodule LightningWeb.SessionToken do
  @moduledoc """
  The session token: how Lightning's own app calls the API as the person using
  it. It is Lightning's Phoenix session cookie and the session token in it, the
  same session a sign-in through the LiveView pages, a provider or
  `POST /api/session` sets, so all three share one session.

  The cookie is sent by the browser on its own, so it counts only on a request
  from Lightning's own pages (`from_own_page?/1`), and a write must also carry
  the session's CSRF token in `x-csrf-token` (`check_csrf/1`). The endpoint
  answers CORS with credentials allowed for `CORS_ORIGIN`, so the origin check
  is what keeps another site, even an allowed one, from reading the API as the
  person: its requests carry the cookie but are treated as carrying nothing.

  `read/1` resolves the session to its person and state. On the API pipeline
  `LightningWeb.Plugs.PersonOrServiceAccountAuth` accepts only a `:signed_in`
  session, as the person, like a personal access token, with `:token_kind`
  `:session` and `:stepped_up_until` assigned for `Lightning.Scope`.
  """
  import Plug.Conn

  alias Lightning.Accounts
  alias Lightning.Accounts.User
  alias LightningWeb.API.Errors
  alias LightningWeb.API.Problem
  alias LightningWeb.UserAuth

  @csrf_header "x-csrf-token"
  @csrf_session_key "_csrf_token"
  @safe_methods ~w(GET HEAD OPTIONS)

  @type state :: :signed_in | :mfa_required | :confirmation_required

  @typedoc """
  A session that names a person. `:mfa_required` is a password sign-in still
  waiting for its MFA code, and `:confirmation_required` an account shut out
  until it confirms its email. Only `:signed_in` acts as the person.
  `stepped_up_until` is set only on a `:signed_in` session.
  """
  @type t :: %{
          user: User.t(),
          state: state(),
          stepped_up_until: DateTime.t() | nil
        }

  @doc """
  Whether the request came from one of Lightning's own pages. A browser says
  so in `Sec-Fetch-Site`, which a page can't set; one that doesn't send it is
  judged by `Origin`, which must be Lightning's own. A request with neither,
  which no current browser sends with a cookie, is not from Lightning's pages.
  """
  @spec from_own_page?(Plug.Conn.t()) :: boolean()
  def from_own_page?(conn) do
    case get_req_header(conn, "sec-fetch-site") do
      [site] -> site == "same-origin"
      [] -> own_origin?(get_req_header(conn, "origin"))
      _several -> false
    end
  end

  defp own_origin?([origin]) do
    ours = URI.parse(LightningWeb.Endpoint.url())
    theirs = URI.parse(origin)

    {theirs.scheme, theirs.host, theirs.port} ==
      {ours.scheme, ours.host, ours.port}
  end

  defp own_origin?(_none_or_several), do: false

  @doc """
  The session the request carries, or `nil` when it carries none, it has
  expired or been revoked, its account may no longer sign in, or the request
  isn't from Lightning's own pages. Fetches the session.
  """
  @spec read(Plug.Conn.t()) :: {t() | nil, Plug.Conn.t()}
  def read(conn) do
    if from_own_page?(conn) do
      conn = fetch_session(conn)
      {token, conn} = UserAuth.session_user_token(conn)
      user = token && Accounts.get_user_by_session_token(token)
      {user && describe(conn, user), conn}
    else
      {nil, conn}
    end
  end

  @doc """
  Whether a request `read/1` found no session for still names one: from
  Lightning's own pages, its session (or remember-me cookie) holds a session
  token that is revoked, expired, or whose account may no longer sign in.
  Call it with the conn `read/1` returned.
  """
  @spec unusable_session?(Plug.Conn.t()) :: boolean()
  def unusable_session?(conn),
    do: from_own_page?(conn) and is_binary(get_session(conn, :user_token))

  @doc """
  Whether the session holds CSRF state, and so can check an `x-csrf-token`.
  The session must already be fetched.
  """
  @spec holds_csrf_state?(Plug.Conn.t()) :: boolean()
  def holds_csrf_state?(conn),
    do: not is_nil(get_session(conn, @csrf_session_key))

  defp describe(conn, user) do
    state =
      cond do
        UserAuth.totp_pending?(conn) -> :mfa_required
        Accounts.locked_out?(user) -> :confirmation_required
        true -> :signed_in
      end

    stepped_up_until =
      if state == :signed_in, do: UserAuth.stepped_up_until(conn, user)

    %{user: user, state: state, stepped_up_until: stepped_up_until}
  end

  @doc """
  `:ok` for a read, or for a write whose `x-csrf-token` header matches the
  session's CSRF token. Otherwise a 400 `invalid_header` naming the header:
  `required` when it is missing, `mismatch` when it doesn't match, for
  instance because signing in renewed the session. The session must already
  be fetched.
  """
  @spec check_csrf(Plug.Conn.t()) :: :ok | {:error, Problem.t()}
  def check_csrf(%Plug.Conn{method: method}) when method in @safe_methods,
    do: :ok

  def check_csrf(conn) do
    state = get_session(conn, @csrf_session_key)

    case get_req_header(conn, @csrf_header) do
      [] ->
        refuse_csrf({"can't be blank", code: :required})

      [token] ->
        if Plug.CSRFProtection.valid_state_and_csrf_token?(state, token),
          do: :ok,
          else: refuse_csrf({"does not match the session", code: :mismatch})

      _several ->
        refuse_csrf({"does not match the session", code: :mismatch})
    end
  end

  defp refuse_csrf(error) do
    entry = Errors.entry({:header, @csrf_header}, error)
    {:error, Problem.new(:invalid_header, errors: [entry])}
  end

  @doc """
  A CSRF token for the session, for the app to send as `x-csrf-token`, and the
  conn with the session holding its state. The same state the LiveView pages
  use, so a token from either works on both. The session must already be
  fetched.
  """
  @spec csrf_token(Plug.Conn.t()) :: {String.t(), Plug.Conn.t()}
  def csrf_token(conn) do
    state =
      conn
      |> get_session(@csrf_session_key)
      |> Plug.CSRFProtection.dump_state_from_session()

    # The masked token is cached per process, and may belong to a session
    # this request has just replaced.
    Plug.CSRFProtection.load_state(conn.secret_key_base, state)
    Process.delete(:plug_masked_csrf_token)
    token = Plug.CSRFProtection.get_csrf_token()

    case Plug.CSRFProtection.dump_state() do
      ^state -> {token, conn}
      new_state -> {token, put_session(conn, @csrf_session_key, new_state)}
    end
  end
end
