defmodule LightningWeb.ProfileLive.MfaComponent do
  @moduledoc """
  Component to enable MFA on a User's account
  """
  use LightningWeb, :live_component

  alias Lightning.Accounts

  @impl true
  def update(%{user: user} = assigns, socket) do
    {:ok,
     socket
     |> assign(assigns)
     |> assign(
       show: user.mfa_enabled,
       current_totp: Accounts.get_user_totp(user),
       editing_totp: nil,
       totp_changeset: nil,
       qrcode_uri: nil
     )}
  end

  @impl true
  def handle_event("show-mfa-options", _params, %{assigns: assigns} = socket) do
    app = "OpenFn"
    # added to allow testing. We need the secret to generate a valid code
    totp_client = Application.get_env(:lightning, :totp_client, NimbleTOTP)
    secret = totp_client.secret()

    qrcode_uri =
      NimbleTOTP.otpauth_uri("#{app}:#{assigns.user.email}", secret, issuer: app)

    editing_totp =
      assigns.current_totp || %Accounts.UserTOTP{user_id: assigns.user.id}

    editing_totp = %{editing_totp | secret: secret}

    totp_changeset = Accounts.UserTOTP.changeset(editing_totp, %{})

    {:noreply,
     assign(socket,
       show: true,
       editing_totp: editing_totp,
       totp_changeset: totp_changeset,
       qrcode_uri: qrcode_uri
     )}
  end

  def handle_event("hide-mfa-options", _params, %{assigns: assigns} = socket) do
    {:noreply, assign(socket, editing_totp: nil, show: assigns.user.mfa_enabled)}
  end

  def handle_event("save_totp", %{"user_totp" => params}, socket) do
    editing_totp = socket.assigns.editing_totp

    case Accounts.upsert_user_totp(editing_totp, params) do
      {:ok, _totp} ->
        {:noreply,
         socket
         |> put_flash(:info, "MFA Setup successfully!")
         |> maybe_redirect_to_backup_codes()}

      {:error, changeset} ->
        {:noreply, assign(socket, totp_changeset: changeset)}
    end
  end

  def handle_event("disable_mfa", _params, socket) do
    current_totp = socket.assigns.current_totp

    case Accounts.delete_user_totp(current_totp) do
      {:ok, _totp} ->
        {:noreply,
         socket
         |> put_flash(:info, "MFA Disabled successfully!")
         |> push_navigate(to: ~p"/profile")}

      {:error, _reason} ->
        {:noreply,
         socket
         |> put_flash(
           :error,
           "Oops! Could not disable 2FA from your account. Please try again later"
         )
         |> push_navigate(to: ~p"/profile")}
    end
  end

  defp maybe_redirect_to_backup_codes(socket) do
    if socket.assigns.user.mfa_enabled do
      push_navigate(socket, to: ~p"/profile")
    else
      token = Accounts.generate_sudo_session_token(socket.assigns.user)
      params = %{sudo_token: Base.encode64(token)}

      push_navigate(socket, to: ~p"/profile/auth/backup_codes?#{params}")
    end
  end

  # NimbleTOTP.otpauth_uri is a safe function
  # sobelow_skip ["XSS.Raw"]
  defp generate_qrcode(uri) do
    uri
    |> EQRCode.encode()
    |> EQRCode.svg(width: 264)
    |> raw()
  end

  defp toggle_btn_event(%{user: user, show: show}) do
    cond do
      user.mfa_enabled ->
        show_modal("disable-mfa-modal")

      show ->
        "hide-mfa-options"

      true ->
        "show-mfa-options"
    end
  end
end
