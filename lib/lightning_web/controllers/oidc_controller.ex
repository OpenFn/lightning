defmodule LightningWeb.OidcController do
  use LightningWeb, :controller

  alias Lightning.Accounts
  alias Lightning.Accounts.User
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
    with {:ok, handler} <- AuthProviders.get_handler(provider) do
      if conn.assigns.current_user do
        UserAuth.redirect_if_user_is_authenticated(conn, nil)
      else
        authorize_url = Handler.authorize_url(handler)
        redirect(conn, external: authorize_url)
      end
    end
  end

  @doc """
  Once the user has completed the authorization flow from above, they are
  returned here, and the authorization code is used to log them in.
  """
  def new(conn, %{"provider" => provider, "code" => code}) do
    with {:ok, handler} <- AuthProviders.get_handler(provider),
         {:ok, token} <- Handler.get_token(handler, code),
         userinfo <- Handler.get_userinfo(handler, token),
         {:ok, email} <- fetch_email(userinfo),
         {:ok, uid} <- fetch_uid(userinfo) do
      handle_sso_login(conn, provider, uid, email, userinfo)
    else
      {:error, :no_email} ->
        conn
        |> put_flash(
          :error,
          "Could not retrieve your email from the provider. Please ensure your email address is accessible."
        )
        |> redirect(to: Routes.user_session_path(conn, :new))

      {:error, _reason} ->
        conn
        |> put_flash(:error, "Authentication failed")
        |> redirect(to: Routes.user_session_path(conn, :new))
    end
  end

  def new(conn, %{"state" => state, "code" => code}) do
    broadcast_message(state, %{code: code})
    close_browser_window(conn)
  end

  def new(conn, %{"error" => error_message, "state" => state}) do
    broadcast_message(state, %{error: error_message})
    close_browser_window(conn)
  end

  defp handle_sso_login(conn, provider, uid, email, userinfo) do
    case Accounts.get_user_by_identity(provider, uid) do
      %User{} = user ->
        do_log_in(conn, user)

      nil ->
        case Accounts.get_user_by_email(email) do
          %User{} = user ->
            Accounts.link_user_identity(user, provider, uid)
            do_log_in(conn, user)

          nil ->
            name = extract_name(userinfo)
            attrs = Map.merge(name, %{email: email})

            case Accounts.register_user_from_sso(attrs, provider, uid) do
              {:ok, user} ->
                do_log_in(conn, user)

              {:error, _changeset} ->
                conn
                |> put_flash(
                  :error,
                  "Could not create your account. Please try again."
                )
                |> redirect(to: Routes.user_session_path(conn, :new))
            end
        end
    end
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

  defp extract_email(userinfo) when is_list(userinfo) do
    userinfo
    |> Enum.find(& &1["primary"])
    |> case do
      %{"email" => email} when is_binary(email) -> email
      _ -> nil
    end
  end

  defp extract_email(%{"email" => email}) when is_binary(email), do: email
  defp extract_email(_), do: nil

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
