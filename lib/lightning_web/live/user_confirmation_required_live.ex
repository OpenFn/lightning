defmodule LightningWeb.UserConfirmationRequiredLive do
  @moduledoc """
  The one page an account locked out pending email confirmation can reach.

  It explains the block and carries both ways out: resend the confirmation link,
  or correct a mistyped address. `Accounts.update_user_email/2` sets
  `confirmed_at`, so the correction form is a complete escape hatch.
  """
  use LightningWeb, :live_view

  alias Lightning.Accounts
  alias LightningWeb.ConfirmationLockout

  require Logger

  @impl true
  def mount(_params, session, socket) do
    user =
      case session["user_token"] do
        nil -> nil
        token -> Accounts.get_user_by_session_token(token)
      end

    if user && Accounts.locked_out?(user) do
      {:ok,
       socket
       |> assign(
         page_title: "Confirm your email",
         current_user: user,
         email_changeset: Accounts.validate_change_user_email(user),
         email_sent: false,
         resend_throttled: false,
         send_failed: false,
         correction_throttled: false,
         email_change_requested: nil
       ), layout: {LightningWeb.Layouts, :app}}
    else
      {:ok, redirect(socket, to: ~p"/projects")}
    end
  end

  @impl true
  def handle_event("resend-confirmation-email", _params, socket) do
    user = socket.assigns.current_user

    case Accounts.remind_account_confirmation(user) do
      {:error, :rate_limited} ->
        {:noreply, assign(socket, :resend_throttled, true)}

      {:ok, _email} ->
        {:noreply,
         assign(socket,
           email_sent: true,
           resend_throttled: false,
           send_failed: false
         )}

      {:error, reason} ->
        Logger.error("Failed to resend confirmation email #{inspect(reason)}")

        {:noreply,
         assign(socket,
           email_sent: false,
           resend_throttled: false,
           send_failed: true
         )}
    end
  end

  def handle_event("validate_email", %{"user" => user_params}, socket) do
    changeset =
      socket.assigns.current_user
      |> Accounts.validate_change_user_email(user_params)
      |> Map.put(:action, :validate_email)

    {:noreply, assign(socket, :email_changeset, changeset)}
  end

  def handle_event("change_email", %{"user" => user_params}, socket) do
    user = socket.assigns.current_user
    changeset = Accounts.validate_change_user_email(user, user_params)
    socket = assign(socket, :correction_throttled, false)

    with {:ok, _data} <- Ecto.Changeset.apply_action(changeset, :validate),
         {:ok, _email} <-
           Accounts.request_email_correction(user, user_params["email"]) do
      {:noreply,
       socket
       |> assign(:email_change_requested, user_params["email"])
       |> assign(:email_changeset, Accounts.validate_change_user_email(user))}
    else
      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply,
         socket
         |> assign(:email_change_requested, nil)
         |> assign(:email_changeset, Map.put(changeset, :action, :validate))}

      {:error, :rate_limited} ->
        {:noreply,
         socket
         |> assign(:correction_throttled, true)
         |> assign(:email_change_requested, nil)
         |> assign(:email_changeset, Map.put(changeset, :action, :validate))}

      {:error, reason} ->
        Logger.error("Failed to request email update #{inspect(reason)}")

        {:noreply,
         socket
         |> assign(:email_change_requested, nil)
         |> assign(
           :email_changeset,
           changeset
           |> Ecto.Changeset.add_error(
             :email,
             "could not be updated, please try again"
           )
           |> Map.put(:action, :validate)
         )}
    end
  end
end
