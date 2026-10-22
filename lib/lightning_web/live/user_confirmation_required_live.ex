defmodule LightningWeb.UserConfirmationRequiredLive do
  @moduledoc """
  The one page an account locked out pending email confirmation can reach.

  It explains the block and carries both ways out: resend the confirmation link,
  or correct a mistyped address. `Accounts.update_user_email/2` sets
  `confirmed_at`, so the correction form is a complete escape hatch. The page
  asks with one event each and shows what the server answers.
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
       |> assign(page_title: "Confirm your email", current_user: user),
       layout: {LightningWeb.Layouts, :app}}
    else
      {:ok, redirect(socket, to: ~p"/projects")}
    end
  end

  # Asks for a new link to the account's own address. The answer is a status
  # the page shows; the rate limit, not a disabled button, bounds resends.
  @impl true
  def handle_event("resend_confirmation_email", _params, socket) do
    user = socket.assigns.current_user

    case Accounts.remind_account_confirmation(user) do
      {:error, :rate_limited} ->
        {:reply,
         %{
           status: "throttled",
           message: ConfirmationLockout.resend_throttled_message()
         }, socket}

      {:ok, _email} ->
        {:reply, %{status: "sent"}, socket}

      {:error, reason} ->
        Logger.error("Failed to resend confirmation email #{inspect(reason)}")
        {:reply, %{status: "failed"}, socket}
    end
  end

  # The page sends the address and the password once, on submit; the server
  # checks both here, as the old `validate_email` did on every change.
  def handle_event("change_email", params, socket) when is_map(params) do
    user = socket.assigns.current_user

    user_params = %{
      "email" => string(params["email"]),
      "current_password" => string(params["currentPassword"])
    }

    changeset = Accounts.validate_change_user_email(user, user_params)

    with {:ok, _data} <- Ecto.Changeset.apply_action(changeset, :validate),
         {:ok, _email} <-
           Accounts.request_email_correction(user, user_params["email"]) do
      {:reply, %{status: "requested", email: user_params["email"]}, socket}
    else
      {:error, %Ecto.Changeset{} = changeset} ->
        reply_error(socket, changeset)

      {:error, :rate_limited} ->
        {:reply, %{status: "throttled"}, socket}

      {:error, reason} ->
        Logger.error("Failed to request email update #{inspect(reason)}")

        reply_error(
          socket,
          Ecto.Changeset.add_error(
            changeset,
            :email,
            "could not be updated, please try again"
          )
        )
    end
  end

  def handle_event("change_email", _params, socket),
    do: reply_error(socket, "Invalid request")

  defp string(value) when is_binary(value), do: value
  defp string(_value), do: ""
end
