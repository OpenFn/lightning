defmodule Lightning.Accounts.UserNotifier do
  @moduledoc """
  The UserNotifier module.
  """

  import Swoosh.Email

  alias Lightning.Mailer

  defp admin(), do: Application.get_env(:lightning, :email_addresses)[:admin]

  # Delivers the email using the application mailer.
  defp deliver(recipient, subject, body) do
    email =
      new()
      |> to(recipient)
      |> from({"Lightning", admin()})
      |> subject(subject)
      |> text_body(body)

    with {:ok, _metadata} <- Mailer.deliver(email) do
      {:ok, email}
    end
  end

  @doc """
  Deliver instructions to confirm account.
  """
  def deliver_confirmation_instructions(user, url) do
    deliver(user.email, "Confirmation instructions", """

    ==============================

    Hi #{user.email},

    You can confirm your account by visiting the URL below:

    #{url}

    If you didn't create an account with us, please ignore this.

    ==============================
    """)
  end

  @doc """
  Deliver an email to notify the user about their account being deleted
  """
  def send_deletion_notification_email(user) do
    deliver(user.email, "Lightning Account Deletion", """

    ==============================

    Hi #{user.first_name},

    Your Lightning account has been scheduled for permanent deletion.

    If you don't want this to happen, please contact #{admin()} as soon as possible.

    ==============================
    """)
  end

  @doc """
  Deliver instructions to reset a user password.
  """
  def deliver_reset_password_instructions(user, url) do
    deliver(user.email, "Reset password instructions", """

    ==============================

    Hi #{user.email},

    You can reset your password by visiting the URL below:

    #{url}

    If you didn't request this change, please ignore this.

    ==============================
    """)
  end

  @doc """
  Deliver instructions to update a user email.
  """
  def deliver_update_email_instructions(user, url) do
    deliver(user.email, "Update email instructions", """

    ==============================

    Hi #{user.email},

    You can change your email by visiting the URL below:

    #{url}

    If you didn't request this change, please ignore this.

    ==============================
    """)
  end

  def deliver_failure_email(users, _run) do
    recipients = Enum.map(users, & &1.email)

    email =
      new()
      |> to(recipients)
      |> from({"Lightning", admin()})
      |> subject("subject")
      |> text_body("body")

    with {:ok, _metadata} <- Mailer.deliver(email) do
      {:ok, email}
    end

    # new_email()
    # |> to(Enum.map(users, fn x -> x.email end))
    # |> from("openfn@openfn.org")
    # |> subject(failure_subject(run))
    # |> text_body(failed_run_text(run))
    # |> html_body(failed_run_html(run))
  end
end
