defmodule Lightning.Accounts.UserNotifier do
  @moduledoc """
  The UserNotifier module.
  """

  import Swoosh.Email

  alias Lightning.Projects
  alias Lightning.Mailer
  alias Lightning.Helpers

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

    Hi #{user.first_name},

    Welcome and thanks for registering a new account on OpenFn/Lightning. Please confirm your account by visiting the URL below:

    #{url}.

    If you didn't create an account with us, please ignore this.

    """)
  end

  @doc """
  Deliver instructions to confirm account.
  """
  def deliver_confirmation_instructions(enroller, user, url) do
    deliver(user.email, "New OpenFn Lightning account", """

    Hi #{user.first_name},

    #{enroller.first_name} has just created an account for you on OpenFn/Lightning. You can complete your registration by visiting the URL below:

    #{url}.

    If you do not wish to have an account, please ignore this email.

    """)
  end

  @doc """
  Deliver email to notify user of his addition of a project.
  """
  def deliver_project_addition_notification(user, project) do
    role = Projects.get_project_user_role(user, project) |> Atom.to_string()

    url =
      "#{LightningWeb.Router.Helpers.url(LightningWeb.Endpoint)}/projects/#{project.id}/w"

    deliver(user.email, "Project #{project.name}", """

    Hi #{user.first_name},

    You've been added to the project "#{project.name}" as #{Helpers.indefinite_article(role)} #{role}.

    Click the link below to check it out:\n\n#{url}

    """)
  end

  defp permanent_deletion_grace() do
    grace_period = Application.get_env(:lightning, :purge_deleted_after_days)

    if grace_period <= 0 do
      "few moments"
    else
      "#{grace_period} days"
    end
  end

  @doc """
  Deliver an email to notify the user about their account being deleted
  """
  def send_deletion_notification_email(user) do
    deliver(user.email, "Lightning Account Deletion", """


    Hi #{user.first_name},

    Your Lightning account has been scheduled for deletion. From now on your account is disabled and you are no longer able to access it.

    It will be permanently deleted in #{permanent_deletion_grace()}. This will delete all of your credentials and remove you from all projects you are participating.

    Note that if you have some ongoing activities in some projects, your account won't be deleted until that activity expires.

    If you don't want this to happen, please contact #{admin()} as soon as possible.

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
  def deliver_update_email_instructions(email, url) do
    deliver(email, "Update email instructions", """

    ==============================

    Hi #{email},

    You can change your email by visiting the URL below:

    #{url}

    If you didn't request this change, please ignore this.

    ==============================
    """)
  end

  @doc """
  Deliver warning to update a user email.
  """
  def deliver_update_email_warning(email, new_email) do
    deliver(email, "Update email warning", """

    ==============================

    Hi #{email},

    You have requested to change your email

    Please visit your inbox (#{new_email}) to activate your account

    If you didn't request this change, please ignore this.

    ==============================
    """)
  end

  defp build_email_body(data, digest) do
    digest_lookup = %{daily: "day", monthly: "month", weekly: "week"}

    """
    #{data.workflow_name}:
    - #{data.successful_workorders} workorders correctly processed this #{digest_lookup[digest]}
    - #{data.rerun_workorders} failed work orders that were rerun and then processed correctly
    - #{data.failed_workorders} work orders that failed/still need addressing

    """
  end

  @doc """
  Deliver a digest for a project to a user.
  """
  def deliver_project_digest(user, project, data, digest) do
    email = user.email
    title = "Weekly digest for project #{project.name}"
    body = Enum.map_join(data, fn d -> build_email_body(d, digest) end)

    deliver(email, title, body)
  end
end
