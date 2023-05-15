defmodule Lightning.Accounts.UserNotifier do
  @moduledoc """
  The UserNotifier module.
  """

  use LightningWeb, :html

  import Swoosh.Email

  alias Lightning.Workorders.SearchParams
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

    url = ~p"/projects/#{project.id}/w"

    deliver(user.email, "Project #{project.name}", """

    Hi #{user.first_name},

    You've been added to the project "#{project.name}" as #{Helpers.indefinite_article(role)} #{role}.

    Click the link below to check it out:\n\n#{url}

    """)
  end

  @doc """
  Deliver an email to notify the user about their account being deleted
  """
  def send_deletion_notification_email(user) do
    deliver(user.email, "Lightning Account Deletion", """


    Hi #{user.first_name},

    Your Lightning account has been scheduled for permanent deletion.

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

  def build_digest_url(workflow, start_date, end_date) do
    uri_params =
      SearchParams.to_uri_params(%{
        "date_after" => start_date,
        "date_before" => end_date,
        "workflow_id" => workflow.id
      })

    path =
      ~p"/projects/#{workflow.project_id}/runs?#{%{"filters" => uri_params}}"

    "#{LightningWeb.Router.Helpers.url(LightningWeb.Endpoint)}#{path}"
  end

  defp build_email(%{
         start_date: start_date,
         end_date: end_date,
         digest: digest,
         workflow: workflow,
         successful_workorders: successful_workorders,
         failed_workorders: failed_workorders
       }) do
    digest_lookup = %{daily: "today", monthly: "this month", weekly: "this week"}

    """
    #{workflow.name}:
    - #{successful_workorders} workorders correctly processed #{digest_lookup[digest]}
    - #{failed_workorders} work orders that failed, crashed or timed out
    Click the link below to view this in the history page:
    #{build_digest_url(workflow, start_date, end_date)}

    """
  end

  @doc """
  Deliver a project digest of daily/weekly or monthly activity to a user.
  """
  def deliver_project_digest(
        digest_data,
        %{
          user: user,
          project: project,
          digest: digest,
          start_date: start_date,
          end_date: end_date
        } = _params
      ) do
    title =
      "#{Atom.to_string(digest) |> String.capitalize()} digest for project #{project.name}"

    body =
      Enum.map_join(digest_data, fn data ->
        build_email(
          Map.merge(data, %{
            start_date: start_date,
            end_date: end_date,
            digest: digest
          })
        )
      end)

    body = """
    Hi #{user.first_name},

    Here's a #{Atom.to_string(digest)} digest for "#{project.name}" project activity since #{start_date |> Calendar.strftime("%a %B %d %Y at %H:%M %Z")}.

    #{body}
    """

    deliver(user.email, title, body)
  end
end
