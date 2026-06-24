defmodule LightningWeb.UserSessionController do
  use LightningWeb, :controller

  alias Lightning.Accounts
  alias Lightning.Accounts.User
  alias LightningWeb.UserAuth

  def new(conn, _params) do
    render(conn, "new.html",
      error_message: nil,
      providers: provider_buttons()
    )
  end

  def create(conn, %{"user" => user_params}) do
    %{"email" => email, "password" => password} = user_params

    Accounts.get_user_by_email_and_password(email, password)
    |> case do
      %User{disabled: true} ->
        conn
        |> put_flash(:error, "This user account is disabled")
        |> render("new.html",
          providers: provider_buttons()
        )

      %User{scheduled_deletion: x} when x != nil ->
        conn
        |> put_flash(
          :error,
          "This user account is scheduled for deletion"
        )
        |> render("new.html",
          providers: provider_buttons()
        )

      %User{mfa_enabled: true} = user ->
        totp_params = Map.take(user_params, ["remember_me"])

        conn
        |> UserAuth.log_in_user(user)
        |> UserAuth.mark_totp_pending()
        |> redirect(to: Routes.user_totp_path(conn, :new, user: totp_params))

      %User{} = user ->
        conn
        |> UserAuth.log_in_user(user)
        |> UserAuth.redirect_with_return_to(user_params)

      {:error, :sso_account} ->
        conn
        |> put_flash(
          :error,
          "This account uses single sign-on. Please log in with your SSO provider."
        )
        |> render("new.html",
          providers: provider_buttons()
        )

      _ ->
        conn
        |> put_flash(:error, "Invalid email or password")
        |> render("new.html",
          providers: provider_buttons()
        )
    end
  end

  def exchange_token(conn, %{"token" => token}) do
    case Accounts.exchange_auth_token(token |> Base.url_decode64!()) do
      nil ->
        conn
        |> put_flash(:error, "Invalid token")
        |> redirect(to: Routes.user_session_path(conn, :new))

      token ->
        conn
        |> UserAuth.new_session(token)
        |> UserAuth.redirect_with_return_to()
    end
  end

  def delete(conn, _params) do
    conn
    |> put_flash(:info, "Logged out successfully.")
    |> UserAuth.log_out_user()
  end

  @doc """
  Returns the two independent kinds of SSO buttons for the login page:

    * `social` — the built-in GitHub/Google buttons, shown when their `SSO_*`
      envs are set (derived straight from the env-based handler builders).
    * `external_url` — the generic "via external provider" button, shown when a
      provider is configured in the admin portal (an `AuthConfig` row).

  Each is driven solely by its own source, so one never suppresses the other.
  """
  def provider_buttons do
    %{
      social: social_providers(),
      external_url: external_provider_url()
    }
  end

  defp social_providers do
    [
      Lightning.AuthProviders.GithubHandler,
      Lightning.AuthProviders.GoogleHandler
    ]
    |> Enum.flat_map(fn handler_module ->
      case handler_module.build() do
        {:ok, handler} ->
          [%{name: handler.name, url: ~p"/authenticate/#{handler.name}"}]

        _ ->
          []
      end
    end)
  end

  defp external_provider_url do
    case Lightning.AuthProviders.get_existing() do
      %Lightning.AuthProviders.AuthConfig{name: name} ->
        ~p"/authenticate/#{name}"

      _ ->
        nil
    end
  end
end
