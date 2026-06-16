defmodule LightningWeb.OidcController do
  use LightningWeb, :controller

  alias Lightning.Accounts
  alias Lightning.Accounts.User
  alias Lightning.AuthProviders
  alias Lightning.AuthProviders.Handler
  alias Lightning.SafetyString
  alias LightningWeb.OauthCredentialHelper
  alias LightningWeb.UserAuth

  action_fallback LightningWeb.FallbackController

  @oauth_state_session_key :sso_oauth_state
  @pending_signup_session_key :sso_pending_signup

  plug :fetch_current_user

  @doc """
  Given a known provider, redirect them to the authorize url on the provider
  """
  def show(conn, %{"provider" => provider}) do
    with {:ok, handler} <- AuthProviders.get_handler(provider) do
      if conn.assigns.current_user do
        UserAuth.redirect_if_user_is_authenticated(conn, nil)
      else
        {conn, authorize_url} =
          authorize_redirect(conn, handler, provider, :login)

        redirect(conn, external: authorize_url)
      end
    end
  end

  @doc """
  Initiates an SSO link flow for an already-authenticated user. The intent,
  provider and current user are carried in a session-bound `state` and the
  user is redirected to the provider's authorize URL. On callback the
  controller links the resulting identity to the current account rather than
  logging in.
  """
  def link(conn, %{"provider" => provider}) do
    with {:ok, handler} <- AuthProviders.get_handler(provider) do
      if conn.assigns.current_user do
        {conn, authorize_url} =
          authorize_redirect(conn, handler, provider, :link)

        redirect(conn, external: authorize_url)
      else
        redirect(conn, to: Routes.user_session_path(conn, :new))
      end
    end
  end

  @doc """
  Once the user has completed the authorization flow from above, they are
  returned here, and the authorization code is used to log them in.
  """
  def new(conn, %{"provider" => provider, "code" => code, "state" => state}) do
    case verify_oauth_state(conn, provider, state) do
      {:ok, intent, conn} ->
        complete_sso_callback(conn, provider, code, intent)

      {:error, conn} ->
        conn
        |> put_flash(:error, "Authentication failed")
        |> redirect(to: Routes.user_session_path(conn, :new))
    end
  end

  # An SSO callback that arrives without our `state` (or with the provider's
  # error) can't be tied back to the browser that started the flow, so we
  # reject it.
  def new(conn, %{"provider" => _provider} = params)
      when is_map_key(params, "code") or is_map_key(params, "error") do
    conn
    |> delete_session(@oauth_state_session_key)
    |> put_flash(:error, "Authentication failed")
    |> redirect(to: Routes.user_session_path(conn, :new))
  end

  def new(conn, %{"state" => state, "code" => code}) do
    broadcast_message(state, %{code: code})
    close_browser_window(conn)
  end

  def new(conn, %{"error" => error_message, "state" => state}) do
    broadcast_message(state, %{error: error_message})
    close_browser_window(conn)
  end

  @doc """
  Renders the confirmation page shown after a successful SSO callback that
  would create a brand-new account. We ask the user to confirm before
  provisioning so they aren't surprised by an account they didn't realise was
  being created.
  """
  def confirm_signup(conn, _params) do
    case get_session(conn, @pending_signup_session_key) do
      %{} = pending ->
        render(conn, :confirm_signup, pending: pending)

      _ ->
        conn
        |> clear_pending_signup()
        |> put_flash(:error, "No pending sign-up to confirm.")
        |> redirect(to: Routes.user_session_path(conn, :new))
    end
  end

  @doc """
  Confirms a pending SSO signup. Creates the account, links the identity, and
  logs the user in.
  """
  def complete_signup(conn, _params) do
    case get_session(conn, @pending_signup_session_key) do
      %{
        "provider" => provider,
        "uid" => uid,
        "email" => email,
        "first_name" => first_name,
        "last_name" => last_name
      } ->
        attrs = %{
          email: email,
          first_name: first_name,
          last_name: last_name
        }

        case Accounts.register_user_from_sso(attrs, provider, uid) do
          {:ok, user} ->
            conn
            |> clear_pending_signup()
            |> do_log_in(user)

          {:error, _changeset} ->
            conn
            |> clear_pending_signup()
            |> put_flash(
              :error,
              "Could not create your account. Please try again."
            )
            |> redirect(to: Routes.user_session_path(conn, :new))
        end

      _ ->
        conn
        |> clear_pending_signup()
        |> put_flash(:error, "No pending sign-up to confirm.")
        |> redirect(to: Routes.user_session_path(conn, :new))
    end
  end

  @doc """
  Cancels a pending SSO signup, clearing the stashed state.
  """
  def cancel_signup(conn, _params) do
    conn
    |> clear_pending_signup()
    |> redirect(to: Routes.user_session_path(conn, :new))
  end

  defp clear_pending_signup(conn) do
    delete_session(conn, @pending_signup_session_key)
  end

  defp complete_sso_callback(conn, provider, code, intent) do
    with {:ok, handler} <- AuthProviders.get_handler(provider),
         {:ok, token} <- Handler.get_token(handler, code),
         userinfo <- Handler.get_userinfo(handler, token),
         {:ok, email} <- fetch_email(userinfo),
         {:ok, uid} <- fetch_uid(userinfo) do
      case intent do
        :link ->
          handle_sso_link(conn, conn.assigns.current_user, provider, uid)

        :login ->
          handle_sso_login(conn, provider, uid, email, userinfo)
      end
    else
      {:error, :no_email} ->
        conn
        |> put_flash(
          :error,
          "Could not retrieve your email from the provider. Please ensure your email address is accessible."
        )
        |> redirect(to: failure_redirect(conn, intent))

      {:error, _reason} ->
        conn
        |> put_flash(:error, "Authentication failed")
        |> redirect(to: failure_redirect(conn, intent))
    end
  end

  defp handle_sso_link(conn, %User{} = current_user, provider, uid) do
    case Accounts.get_user_by_identity(provider, uid) do
      %User{id: id} when id == current_user.id ->
        conn
        |> put_flash(
          :info,
          "Your #{AuthProviders.display_name(provider)} account is already linked."
        )
        |> redirect(to: ~p"/profile")

      %User{} ->
        conn
        |> put_flash(
          :error,
          "This #{AuthProviders.display_name(provider)} identity is already linked to a different account."
        )
        |> redirect(to: ~p"/profile")

      nil ->
        case Accounts.link_user_identity(current_user, provider, uid) do
          {:ok, _identity} ->
            conn
            |> put_flash(
              :info,
              "Linked your #{AuthProviders.display_name(provider)} account."
            )
            |> redirect(to: ~p"/profile")

          {:error, :identity_already_linked} ->
            conn
            |> put_flash(
              :error,
              "This #{AuthProviders.display_name(provider)} identity is already linked to a different account."
            )
            |> redirect(to: ~p"/profile")

          {:error, _reason} ->
            conn
            |> put_flash(
              :error,
              "Could not link your #{AuthProviders.display_name(provider)} account. Please try again."
            )
            |> redirect(to: ~p"/profile")
        end
    end
  end

  defp handle_sso_login(conn, provider, uid, email, userinfo) do
    case Accounts.get_user_by_identity(provider, uid) do
      %User{} = user ->
        do_log_in(conn, user)

      nil ->
        if email_verified?(userinfo) do
          handle_unlinked_identity(conn, provider, uid, email, userinfo)
        else
          conn
          |> put_flash(
            :error,
            "Your #{AuthProviders.display_name(provider)} email address has not been verified. Please verify it with #{AuthProviders.display_name(provider)} and try signing in again."
          )
          |> redirect(to: Routes.user_session_path(conn, :new))
        end
    end
  end

  defp handle_unlinked_identity(conn, provider, uid, email, userinfo) do
    case Accounts.get_user_by_email(email) do
      %User{} ->
        conn
        |> put_flash(
          :info,
          "An account already exists for #{email}. Sign in and link your #{AuthProviders.display_name(provider)} account from your profile settings to use single sign-on."
        )
        |> redirect(to: Routes.user_session_path(conn, :new))

      nil ->
        request_signup_confirmation(conn, provider, uid, email, userinfo)
    end
  end

  defp request_signup_confirmation(conn, provider, uid, email, userinfo) do
    %{first_name: first_name, last_name: last_name} = extract_name(userinfo)

    pending = %{
      "provider" => provider,
      "uid" => uid,
      "email" => email,
      "first_name" => first_name,
      "last_name" => last_name
    }

    conn
    |> put_session(@pending_signup_session_key, pending)
    |> redirect(to: ~p"/authenticate/signup/confirm")
  end

  defp do_log_in(conn, %{mfa_enabled: true} = user) do
    conn
    |> UserAuth.log_in_user(user)
    |> UserAuth.mark_totp_pending()
    |> redirect(
      to: Routes.user_totp_path(conn, :new, user: %{"remember_me" => "true"})
    )
  end

  defp do_log_in(conn, user) do
    conn
    |> UserAuth.log_in_user(user)
    |> UserAuth.redirect_with_return_to(%{"remember_me" => "true"})
  end

  defp fetch_email(userinfo) do
    case extract_email(userinfo) do
      nil -> {:error, :no_email}
      email -> {:ok, email}
    end
  end

  defp fetch_uid(userinfo) do
    case extract_uid(userinfo) do
      nil -> {:error, :no_uid}
      uid -> {:ok, uid}
    end
  end

  defp extract_email(%{"email" => email}) when is_binary(email), do: email
  defp extract_email(_), do: nil

  defp email_verified?(%{"email_verified" => verified}),
    do: verified in [true, "true"]

  defp email_verified?(_), do: false

  defp extract_uid(%{"sub" => sub}) when is_binary(sub), do: sub
  defp extract_uid(%{"id" => id}) when is_integer(id), do: to_string(id)
  defp extract_uid(%{"id" => id}) when is_binary(id), do: id
  defp extract_uid(_), do: nil

  defp extract_name(%{"given_name" => first, "family_name" => last})
       when is_binary(first) and is_binary(last) do
    %{first_name: first, last_name: last}
  end

  defp extract_name(%{"name" => name}) when is_binary(name) do
    case String.split(name, " ", parts: 2) do
      [first, last] -> %{first_name: first, last_name: last}
      [first] -> %{first_name: first, last_name: ""}
    end
  end

  defp extract_name(_), do: %{first_name: "", last_name: ""}

  # Mints a single-use, session-bound state and returns the provider authorize
  # URL carrying it. The nonce lives in the session (the secret the attacker
  # can't read); the encrypted state carries the same nonce plus the intent,
  # provider and — for the link flow — the user it must remain bound to.
  defp authorize_redirect(conn, handler, provider, intent) do
    nonce = Base.url_encode64(:crypto.strong_rand_bytes(24), padding: false)

    user_id =
      case conn.assigns.current_user do
        %User{id: id} -> id
        _ -> ""
      end

    state =
      SafetyString.encode([
        nonce,
        to_string(intent),
        provider,
        to_string(user_id)
      ])

    conn = put_session(conn, @oauth_state_session_key, nonce)

    {conn, Handler.authorize_url(handler, state: state)}
  end

  # Verifies the callback `state` against the nonce stashed in the session. The
  # nonce is consumed (single-use) regardless of outcome. On the link flow the
  # state must also still belong to the currently authenticated user.
  defp verify_oauth_state(conn, provider, state) do
    session_nonce = get_session(conn, @oauth_state_session_key)
    conn = delete_session(conn, @oauth_state_session_key)

    with [nonce, intent, state_provider, user_id] <- decode_oauth_state(state),
         true <- is_binary(session_nonce),
         true <- Plug.Crypto.secure_compare(nonce, session_nonce),
         true <- state_provider == provider,
         {:ok, intent} <- authorize_intent(conn, intent, user_id) do
      {:ok, intent, conn}
    else
      _ -> {:error, conn}
    end
  end

  defp decode_oauth_state(state) when is_binary(state) do
    SafetyString.decode(state)
  rescue
    _ -> :error
  end

  defp decode_oauth_state(_state), do: :error

  defp authorize_intent(_conn, "login", _user_id), do: {:ok, :login}

  defp authorize_intent(conn, "link", user_id) do
    case conn.assigns.current_user do
      %User{id: id} ->
        if to_string(id) == user_id, do: {:ok, :link}, else: :error

      _ ->
        :error
    end
  end

  defp authorize_intent(_conn, _intent, _user_id), do: :error

  defp failure_redirect(conn, intent) do
    if intent == :link && conn.assigns.current_user do
      ~p"/profile"
    else
      Routes.user_session_path(conn, :new)
    end
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
