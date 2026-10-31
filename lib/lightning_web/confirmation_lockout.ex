defmodule LightningWeb.ConfirmationLockout do
  @moduledoc false
  # Deliberately single-file and free of call-site knowledge: this is expected to be
  # absorbed into a general account-state check and deleted.

  use LightningWeb, :verified_routes

  @message "Your account is blocked pending email confirmation. " <>
             "Confirm your email address, or update it below and we will send a new link."

  @resend_throttled_message "You've asked for this a few times recently. " <>
                              "Check your inbox and spam folder; you can request another in a few minutes."

  # Routes a locked-out account must still reach. Exact entries must not move
  # into the prefix list: ["users"] or ["profile"] as prefixes would let through
  # /profile/tokens and /profile/auth/backup_codes/print. `/users/log_out` is
  # absent because it lives in the unauthenticated scope and never reaches here.
  @allowed_prefixes [
    # /users/confirm/:token — the link in the confirmation email
    ["users", "confirm"],
    # /profile/confirm_email/:token — the link sent when correcting the address
    ["profile", "confirm_email"]
  ]

  @allowed_paths [
    # The redirect target itself; without it every locked-out user loops.
    ["users", "confirm-required"],
    # The same resend from a bookmarked link; idempotent, and already guarded on
    # confirmed_at: nil.
    ["users", "send-confirmation-email"],
    # So an unconfirmed account with MFA can still complete the second factor.
    ["users", "two-factor"]
  ]

  @spec allowed_path?([String.t()]) :: boolean()
  def allowed_path?(path_info) when is_list(path_info) do
    path_info in @allowed_paths or
      Enum.any?(@allowed_prefixes, &List.starts_with?(path_info, &1))
  end

  @doc "Where a blocked HTML request lands."
  @spec redirect_path() :: String.t()
  def redirect_path, do: ~p"/users/confirm-required"

  @spec message() :: String.t()
  def message, do: @message

  @doc "What to say when `Accounts.remind_account_confirmation/1` refuses to send."
  @spec resend_throttled_message() :: String.t()
  def resend_throttled_message, do: @resend_throttled_message
end
