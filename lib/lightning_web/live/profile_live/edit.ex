defmodule LightningWeb.ProfileLive.Edit do
  @moduledoc """
  LiveView for user profile page.

  Every action is on the signed-in user, read again from the database, never
  on an id the page sends. The delete route checks the `:delete_account`
  policy before the modal opens, and the delete action runs only with that
  modal open.

  The `/profile` route's `delete_modal` metadata names the deletion modal.
  Lightning's own is drawn by the design-system page; any other module is a
  LiveComponent drawn beside it, as before. A configured `gdpr_preferences`
  component is drawn beside the page too.
  """
  use LightningWeb, :live_view

  alias Lightning.Accounts
  alias Lightning.Accounts.User
  alias Lightning.Policies.Permissions
  alias Lightning.Policies.Users
  alias Lightning.VersionControl
  alias LightningWeb.Components.GithubComponents

  require Logger

  on_mount {LightningWeb.Hooks, :assign_projects}

  @default_delete_modal LightningWeb.Components.UserDeletionModal

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      VersionControl.subscribe(socket.assigns.current_user)
    end

    {:ok,
     socket
     |> assign(
       active_menu_item: :profile,
       page_title: "User Profile",
       editing_totp: nil,
       gdpr_preferences: Lightning.Config.gdpr_preferences(),
       hosted_delete_modal: hosted_delete_modal(socket),
       github_connect_href:
         if(VersionControl.github_enabled?(),
           do: GithubComponents.authorize_url()
         )
     )
     |> load()}
  end

  # The modal the `/profile` route names, when it isn't Lightning's own.
  defp hosted_delete_modal(socket) do
    socket.router
    |> Phoenix.Router.route_info("GET", ~p"/profile", nil)
    |> Map.get(:delete_modal)
    |> case do
      @default_delete_modal -> nil
      modal -> modal
    end
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply,
     apply_action(
       socket,
       socket.assigns.live_action,
       params
     )}
  end

  @impl true
  def handle_info(
        %Lightning.VersionControl.Events.OauthTokenAdded{},
        socket
      ) do
    {:noreply,
     socket
     |> put_flash(:info, "GitHub account linked successfully")
     |> push_navigate(to: ~p"/profile")}
  end

  def handle_info(
        %Lightning.VersionControl.Events.OauthTokenFailed{},
        socket
      ) do
    {:noreply,
     socket
     |> put_flash(
       :error,
       "Oops! GitHub account failed to link. Please try again"
     )}
  end

  defp apply_action(socket, :edit, _params),
    do: socket |> assign(:deleting, false) |> assign_deletion(false)

  defp apply_action(socket, :delete, %{"id" => user_id}) do
    user = socket.assigns.current_user

    if can_delete_account?(user, user_id) do
      socket
      |> assign(:deleting, true)
      |> assign_deletion(Accounts.has_activity_in_projects?(user))
    else
      socket
      |> assign(:deleting, false)
      |> assign_deletion(false)
      |> put_flash(:error, "You can't perform this action")
      |> push_patch(to: ~p"/profile")
    end
  end

  defp can_delete_account?(current_user, user_id) do
    with {:ok, id} <- Ecto.UUID.cast(user_id),
         %User{} = user <- Accounts.get_user(id) do
      Permissions.can?(Users, :delete_account, current_user, user)
    else
      _ -> false
    end
  end

  # Activity in projects is only read when the deletion modal opens.
  defp assign_deletion(socket, has_activity) do
    user = socket.assigns.current_user

    assign(socket, :deletion, %{
      href: ~p"/profile/#{user.id}/delete",
      hasActivityInProjects: has_activity,
      blocked: has_activity and not is_nil(user.scheduled_deletion)
    })
  end

  # The signed-in user, read again, and what the page shows of them.
  defp load(socket) do
    user = Accounts.get_user!(socket.assigns.current_user.id)

    assign(socket, current_user: user, github_status: github_status(user))
  end

  defp github_status(user) do
    cond do
      VersionControl.oauth_token_valid?(user.github_oauth_token) -> "connected"
      user.github_oauth_token -> "expired"
      true -> "none"
    end
  end

  @impl true
  def handle_event("save_basic_info", params, socket) when is_map(params) do
    # Only the fields sent; a missing one keeps its value, as the old form did.
    attrs =
      %{
        "first_name" => params["firstName"],
        "last_name" => params["lastName"],
        "contact_preference" => params["contactPreference"]
      }
      |> Map.reject(fn {_key, value} -> is_nil(value) end)

    case Accounts.update_user_info(socket.assigns.current_user, attrs) do
      {:ok, _user} ->
        {:reply, %{},
         socket
         |> put_flash(:info, "User information updated successfully")
         |> load()}

      {:error, changeset} ->
        reply_error(socket, changeset)
    end
  end

  def handle_event("change_email", params, socket) when is_map(params) do
    user = socket.assigns.current_user

    changeset =
      Accounts.validate_change_user_email(user, %{
        "email" => params["email"],
        "current_password" => params["currentPassword"]
      })

    with {:ok, %{email: email}} <-
           Ecto.Changeset.apply_action(changeset, :validate),
         {:ok, _email} <- Accounts.request_email_update(user, email) do
      {:reply, %{},
       put_flash(
         socket,
         :info,
         "You will receive an email with instructions shortly."
       )}
    else
      {:error, %Ecto.Changeset{} = changeset} ->
        reply_error(socket, changeset)

      {:error, reason} ->
        Logger.error("Failed to request email update #{inspect(reason)}")
        reply_error(socket, "Failed to request email update")
    end
  end

  # As before, the user is signed in again with a new session.
  def handle_event("change_password", params, socket) when is_map(params) do
    case Accounts.update_user_password(
           socket.assigns.current_user,
           params["currentPassword"],
           %{
             "password" => params["password"],
             "password_confirmation" => params["passwordConfirmation"]
           }
         ) do
      {:ok, user} ->
        token = Accounts.generate_auth_token(user) |> Base.url_encode64()

        {:reply, %{},
         socket
         |> put_flash(:info, "Password changed successfully.")
         |> redirect(
           to: Routes.user_session_path(socket, :exchange_token, token)
         )}

      {:error, changeset} ->
        reply_error(socket, changeset)
    end
  end

  # The new secret goes back only in the reply; the LiveView keeps it for
  # `confirm_mfa`.
  def handle_event("start_mfa_setup", _params, socket) do
    user = socket.assigns.current_user
    app = "OpenFn"
    # added to allow testing. We need the secret to generate a valid code
    totp_client = Application.get_env(:lightning, :totp_client, NimbleTOTP)
    secret = totp_client.secret()

    qrcode_uri =
      NimbleTOTP.otpauth_uri("#{app}:#{user.email}", secret, issuer: app)

    editing_totp =
      (Accounts.get_user_totp(user) || %Accounts.UserTOTP{user_id: user.id})
      |> Map.put(:secret, secret)

    {:reply,
     %{
       secret: Base.encode32(secret, padding: false),
       qrCodeSrc: qrcode_src(qrcode_uri)
     }, assign(socket, :editing_totp, editing_totp)}
  end

  def handle_event("confirm_mfa", %{"code" => code}, socket)
      when is_binary(code) do
    case socket.assigns.editing_totp do
      %Accounts.UserTOTP{} = editing_totp ->
        confirm_mfa(socket, editing_totp, code)

      nil ->
        reply_error(socket, "Invalid request")
    end
  end

  def handle_event("disable_mfa", _params, socket) do
    with %Accounts.UserTOTP{} = totp <-
           Accounts.get_user_totp(socket.assigns.current_user),
         {:ok, _totp} <- Accounts.delete_user_totp(totp) do
      {:reply, %{},
       socket
       |> assign(:editing_totp, nil)
       |> put_flash(:info, "MFA Disabled")
       |> load()}
    else
      _ ->
        reply_error(
          socket,
          "Oops! Could not disable 2FA from your account. Please try again later"
        )
    end
  end

  def handle_event("disconnect_github", _params, socket) do
    case VersionControl.delete_github_oauth_grant(socket.assigns.current_user) do
      {:ok, _user} ->
        {:reply, %{},
         socket
         |> put_flash(:info, "GitHub connection removed successfully")
         |> load()}

      {:error, _error} ->
        reply_error(
          socket,
          "Oops! An error occurred while trying to remove the connection. Please try again"
        )
    end
  end

  def handle_event("set_experimental_features", %{"on" => on}, socket)
      when is_boolean(on) do
    case Accounts.update_user_preferences(socket.assigns.current_user, %{
           "experimental_features" => on
         }) do
      {:ok, _user} ->
        {:reply, %{},
         socket
         |> put_flash(:info, "Experimental features updated successfully")
         |> load()}

      {:error, _changeset} ->
        reply_error(
          socket,
          "Failed to update experimental features. Please try again."
        )
    end
  end

  # Only from Lightning's deletion modal, which the delete route opens after
  # its policy check, and on the account as it is now.
  def handle_event("delete_account", %{"email" => email}, socket)
      when is_binary(email) do
    if socket.assigns.deleting and is_nil(socket.assigns.hosted_delete_modal) do
      delete_account(socket, socket.assigns.current_user, email)
    else
      reply_error(socket, "You can't perform this action")
    end
  end

  def handle_event(event, _params, socket)
      when event in [
             "save_basic_info",
             "change_email",
             "change_password",
             "confirm_mfa",
             "set_experimental_features",
             "delete_account"
           ],
      do: reply_error(socket, "Invalid request")

  defp confirm_mfa(socket, editing_totp, code) do
    user = socket.assigns.current_user

    case Accounts.upsert_user_totp(editing_totp, %{"code" => code}) do
      {:ok, _totp} when user.mfa_enabled ->
        {:reply, %{},
         socket
         |> assign(:editing_totp, nil)
         |> put_flash(:info, "MFA Setup")
         |> load()}

      # After a first setup the recovery codes page opens, with a sudo token.
      {:ok, _totp} ->
        token = Accounts.generate_sudo_session_token(user)
        params = %{sudo_token: Base.encode64(token)}

        {:reply, %{},
         socket
         |> put_flash(:info, "MFA Setup")
         |> push_navigate(to: ~p"/profile/auth/backup_codes?#{params}")}

      {:error, changeset} ->
        reply_error(socket, changeset)
    end
  end

  # A scheduled account can't sign in, so the old modal's "delete now" for
  # one never runs here; it is refused like any other.
  defp delete_account(socket, %User{scheduled_deletion: nil} = user, email) do
    case Accounts.schedule_user_deletion(user, email) do
      {:ok, %User{}} ->
        {:reply, %{},
         socket
         |> put_flash(:info, "User scheduled for deletion")
         |> push_navigate(to: Routes.user_session_path(socket, :delete))}

      {:error, %Ecto.Changeset{} = changeset} ->
        reply_error(socket, deletion_error(changeset))
    end
  end

  defp delete_account(socket, _user, _email),
    do: reply_error(socket, "You can't perform this action")

  # The changeset puts every refusal on the email field; the modal shows the
  # first as its one line.
  defp deletion_error(changeset) do
    changeset
    |> LightningWeb.CoreComponents.translate_errors()
    |> Map.values()
    |> List.flatten()
    |> List.first("Please fix the errors below.")
  end

  # The image is a data URI.
  defp qrcode_src(uri) do
    svg =
      uri
      |> EQRCode.encode()
      |> EQRCode.svg(width: 264)

    "data:image/svg+xml;base64," <> Base.encode64(svg)
  end

  # The shapes the design system's ProfilePage props expect.
  defp user_json(%User{} = user) do
    %{
      id: user.id,
      firstName: user.first_name,
      lastName: user.last_name,
      email: user.email,
      contactPreference: user.contact_preference,
      insertedAt: user.inserted_at
    }
  end
end
