defmodule LightningWeb.OidcController do
  use LightningWeb, :controller

  alias Lightning.Accounts
  alias Lightning.AuthProviders
  alias Lightning.AuthProviders.Handler
  alias LightningWeb.OauthCredentialHelper
  alias LightningWeb.UserAuth

  action_fallback LightningWeb.FallbackController

  plug :fetch_current_user

  @doc """
  Given a known provider, redirect them to the authorize url on the provider
  """
  def show(conn, %{"provider" => provider}) do
    case AuthProviders.get_handler(provider) do
      {:ok, handler} ->
        if conn.assigns.current_user do
          UserAuth.redirect_if_user_is_authenticated(conn, nil)
        else
          state = random_token()
          nonce = random_token()

          conn
          |> put_pending(state, nonce)
          |> redirect(external: Handler.authorize_url(handler, state, nonce))
        end

      # A missing provider keeps its 404 via the fallback controller; any other
      # build failure (e.g. an unreachable or insecure discovery url) sends the
      # user back to login rather than surfacing a 500.
      {:error, :not_found} = error ->
        error

      {:error, _reason} ->
        login_redirect(conn)
    end
  end

  @doc """
  Once the user has completed the authorization flow from above, they are
  returned here, and the authorization code is used to log them in.
  """
  def new(conn, %{"provider" => provider, "code" => code} = params) do
    # Consume this flow's state from the session up front (a matching entry also
    # yields its nonce), so a replay can't reuse it and other in-flight flows
    # are left intact.
    {nonce, conn} = pop_pending(conn, params["state"])

    # Resolve the handler separately from the login chain: a missing provider
    # keeps its 404, and any other build failure (unreachable/insecure discovery)
    # sends the user back to login rather than rendering a token-error page.
    case AuthProviders.get_handler(provider) do
      {:ok, handler} ->
        complete_login(conn, handler, code, nonce)

      {:error, :not_found} = error ->
        error

      {:error, _reason} ->
        login_redirect(conn)
    end
  end

  # Any other callback carrying a provider (a consent-denial `error`, or a bare
  # revisit with neither `code` nor `error`) redirects to login rather than
  # crashing or falling through to the credential-popup clause.
  def new(conn, %{"provider" => _provider} = params) do
    {_nonce, conn} = pop_pending(conn, params["state"])
    login_redirect(conn)
  end

  def new(conn, %{"state" => state, "code" => code}) do
    broadcast_message(state, %{code: code})
    close_browser_window(conn)
  end

  def new(conn, %{"error" => error_message, "state" => state}) do
    broadcast_message(state, %{error: error_message})
    close_browser_window(conn)
  end

  def new(conn, _params) do
    redirect(conn, to: Routes.user_session_path(conn, :new))
  end

  defp complete_login(conn, handler, code, nonce) do
    with :ok <- check_state(nonce),
         {:ok, token} <- Handler.get_token(handler, code),
         {:ok, claims} <- Handler.verify_id_token(handler, token, nonce),
         {:ok, email} <- verified_email(handler, token, claims) do
      log_in_by_email(conn, email)
    else
      # Our own checks (state, id_token, email_verified) and a transport failure
      # fail the login without revealing which one tripped.
      {:error, reason} when is_atom(reason) ->
        login_redirect(conn)

      # A token-endpoint error body (map or string) keeps its rendered response.
      {:error, body} ->
        {:error, body}
    end
  end

  defp login_redirect(conn) do
    conn
    |> put_flash(:error, "We couldn't sign you in. Please try again.")
    |> redirect(to: Routes.user_session_path(conn, :new))
  end

  # In-flight SSO flows are kept as a small `state => nonce` map so concurrent
  # or double-fired logins don't clobber each other.
  defp put_pending(conn, state, nonce) do
    pending =
      conn
      |> get_session(:oidc_pending)
      |> Kernel.||(%{})
      |> cap_pending()
      |> Map.put(state, nonce)

    put_session(conn, :oidc_pending, pending)
  end

  # Bound the number of in-flight flows before adding this one, so a burst of
  # stale states can't grow the session unboundedly nor crowd out the state
  # we're about to store (which must survive to complete the current login).
  # Eviction drops existing entries in map (not insertion) order; concurrent
  # unfinished flows in a single session are rare enough that which one goes
  # doesn't matter.
  defp cap_pending(pending) when map_size(pending) >= 5,
    do: pending |> Enum.drop(map_size(pending) - 4) |> Map.new()

  defp cap_pending(pending), do: pending

  defp pop_pending(conn, state) when is_binary(state) do
    pending = get_session(conn, :oidc_pending) || %{}
    {nonce, remaining} = Map.pop(pending, state)
    {nonce, put_session(conn, :oidc_pending, remaining)}
  end

  defp pop_pending(conn, _state), do: {nil, conn}

  defp check_state(nonce) when is_binary(nonce), do: :ok
  defp check_state(_nonce), do: {:error, :invalid_state}

  defp verified_email(handler, token, claims) do
    cond do
      # The id_token carries both email and a verified flag: trust it directly.
      is_binary(claims["email"]) and not is_nil(claims["email_verified"]) ->
        accept_email(handler, claims["email"], claims["email_verified"])

      # The id_token carries an email but no verified flag, and the operator has
      # opted into trusting this provider: no userinfo round-trip needed.
      is_binary(claims["email"]) and handler.allow_unverified_email ->
        {:ok, claims["email"]}

      # Otherwise consult userinfo (bound to the subject) for the email /
      # email_verified the id_token didn't carry — so a provider that puts
      # `email` in the id_token but `email_verified` only in userinfo still works.
      true ->
        from_userinfo(handler, token, claims)
    end
  end

  defp from_userinfo(handler, token, claims) do
    userinfo = bound_userinfo(handler, token, claims["sub"])

    cond do
      # The id_token's email (its own email_verified was absent, hence we're
      # here); take the verified flag from userinfo, but only when userinfo isn't
      # attesting a different email (else its flag wouldn't vouch for this one).
      is_binary(claims["email"]) ->
        verified =
          if same_email?(userinfo["email"], claims["email"]),
            do: userinfo["email_verified"]

        accept_email(handler, claims["email"], verified)

      # Both the email and its verified flag come from userinfo.
      is_binary(userinfo["email"]) ->
        accept_email(handler, userinfo["email"], userinfo["email_verified"])

      true ->
        {:error, :missing_email}
    end
  end

  defp accept_email(handler, email, verified) do
    cond do
      not is_binary(email) -> {:error, :missing_email}
      email_verified?(handler, verified) -> {:ok, email}
      true -> {:error, :email_not_verified}
    end
  end

  # Fetch userinfo only when it's bound to the authenticated id_token subject;
  # a missing/mismatched/failed response yields no claims, so the caller falls
  # through to a verification failure rather than trusting an unbound email.
  defp bound_userinfo(handler, token, sub) do
    userinfo = Handler.get_userinfo(handler, token)

    if is_binary(sub) and userinfo["sub"] == sub, do: userinfo, else: %{}
  rescue
    _ -> %{}
  end

  # Require the provider to assert `email_verified` (an absent or false claim is
  # rejected), unless the operator has explicitly marked this provider trusted
  # for unverified emails.
  defp email_verified?(%{allow_unverified_email: true}, _verified), do: true
  defp email_verified?(_handler, verified), do: verified in [true, "true"]

  # userinfo's email_verified only vouches for the id_token email when userinfo
  # isn't naming a different address. An absent userinfo email (it carried only
  # the flag) is fine; a present one must match, case-insensitively. A malformed
  # (non-string) email is treated as a mismatch so we fail closed, not crash.
  defp same_email?(nil, _id_token_email), do: true

  defp same_email?(userinfo_email, id_token_email)
       when is_binary(userinfo_email),
       do: String.downcase(userinfo_email) == String.downcase(id_token_email)

  defp same_email?(_userinfo_email, _id_token_email), do: false

  defp log_in_by_email(conn, email) do
    case Accounts.get_user_by_email(email) do
      nil ->
        conn
        |> put_flash(:error, "Could not find user account")
        |> redirect(to: Routes.user_session_path(conn, :new))

      user ->
        log_in_via_sso(conn, user)
    end
  end

  # Shares the account-state gate (Accounts.login_blocked?/1) with the password
  # login path, keeping this path's own redirect responses.
  defp log_in_via_sso(conn, user) do
    if Accounts.login_blocked?(user) do
      conn
      |> put_flash(
        :error,
        UserAuth.login_blocked_message(Accounts.login_blocked_reason(user))
      )
      |> redirect(to: Routes.user_session_path(conn, :new))
    else
      if user.mfa_enabled do
        conn
        |> UserAuth.log_in_user(user)
        |> UserAuth.mark_totp_pending()
        |> redirect(
          to: Routes.user_totp_path(conn, :new, user: %{"remember_me" => "true"})
        )
      else
        conn
        |> UserAuth.log_in_user(user)
        |> UserAuth.redirect_with_return_to(%{"remember_me" => "true"})
      end
    end
  end

  defp random_token do
    32 |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false)
  end

  defp broadcast_message(state, data) do
    [subscription_id, mod, component_id, current_tab] =
      OauthCredentialHelper.decode_state(state)

    OauthCredentialHelper.broadcast_forward(
      subscription_id,
      mod,
      data
      |> Map.put(:id, component_id)
      |> Map.put(:current_tab, current_tab)
    )
  end

  defp close_browser_window(conn) do
    html(conn, """
      <html>
        <body>
          <script type="text/javascript">
            window.onload = function() {
              window.close();
            }
          </script>
        </body>
      </html>
    """)
  end
end
