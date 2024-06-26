defmodule Lightning.Accounts.UserNotifier do
  @moduledoc """
  The UserNotifier module.
  """

  use LightningWeb, :html

  use Oban.Worker,
    queue: :background,
    max_attempts: 1

  import Swoosh.Email

  alias Lightning.Accounts.User
  # alias Lightning.Helpers
  alias Lightning.Mailer
  alias Lightning.Projects
  alias Lightning.Projects.Project
  alias Lightning.WorkOrders.SearchParams

  defp admin, do: Lightning.Config.instance_admin_email()

  @impl Oban.Worker
  def perform(%{
        args: %{
          "type" => "project_addition",
          "project_user_id" => project_user_id
        }
      }) do
    project_user =
      project_user_id
      |> Projects.get_project_user!()
      |> Lightning.Repo.preload([:user, :project])

    deliver_project_addition_notification(
      project_user.user,
      project_user.project
    )

    :ok
  end

  # Delivers the email using the application mailer.
  defp deliver(recipient, subject, body) do
    email =
      new()
      |> to(recipient)
      |> from({Lightning.Config.email_sender_name(), admin()})
      |> subject(subject)
      |> text_body(body)

    with {:ok, _metadata} <- Mailer.deliver(email) do
      {:ok, email}
    end
  end

  @doc """
  Deliver instructions to confirm account.
  """
  def deliver_confirmation_instructions(user, token) do
    deliver(user.email, "Confirm your OpenFn account", """

    Hi #{user.first_name},

    Welcome, and thanks for registering a new account on OpenFn. Please confirm your account by visiting the URL below:

    #{url(LightningWeb.Endpoint, ~p"/users/confirm/#{token}")} .

    OpenFn
    """)
  end

  @doc """
  Deliver instructions to confirm account.
  """
  def deliver_confirmation_instructions(enroller, user, token) do
    deliver(user.email, "New OpenFn Lightning account", """

    Hi #{user.first_name},

    #{enroller.first_name} has just created an account for you on OpenFn. You can complete your registration by visiting the URL below:

    #{url(LightningWeb.Endpoint, ~p"/users/confirm/#{token}")} .

    If you do not wish to have an account, please ignore this email.

    """)
  end

  @doc """
  Deliver email to notify user of his addition of a project.
  """
  def deliver_project_addition_notification(user, project) do
    role = Projects.get_project_user_role(user, project) |> Atom.to_string()

    url = LightningWeb.RouteHelpers.project_dashboard_url(project.id)

    deliver(user.email, "Project #{project.name}", """

    Hi #{user.first_name},

    You've been granted "#{role}" access to the "#{project.name}" project on OpenFn.

    Visit the URL below to check it out:\n\n#{url}

    OpenFn

    """)
  end

  defp permanent_deletion_grace do
    grace_period = Lightning.Config.purge_deleted_after_days()

    cond do
      grace_period <= 0 -> "a few minutes"
      grace_period == 1 -> "#{grace_period} day"
      true -> "#{grace_period} days"
    end
  end

  @doc """
  Deliver an email to notify the user about a data retention setting change made in their project
  """
  @spec send_data_retention_change_email(
          user :: map(),
          updated_project :: map()
        ) :: {:ok, term()} | {:error, term()}
  def send_data_retention_change_email(user, updated_project) do
    deliver(
      user.email,
      "An update to your #{updated_project.name} retention policy",
      """
      Hi #{user.first_name},

      We'd like to inform you that the data retention policy for your project, #{updated_project.name}, was recently updated.
      If you haven't approved this change, we recommend that you log in into your OpenFn account to reset the policy.

      Should you require assistance with your account, feel free to contact #{admin()}.

      Best regards,
      The OpenFn Team
      """
    )
  end

  @doc """
  Deliver an email to notify the user about their account being deleted
  """
  def send_deletion_notification_email(user) do
    deliver(user.email, "Lightning Account Deletion", """


    Hi #{user.first_name},

    Your Lightning account has been scheduled for deletion. It has been disabled and you will no longer be able to login.

    It will be permanently deleted in #{permanent_deletion_grace()}. This will delete all of your credentials and remove you from all projects.

    Note that if you have auditable events associated with projects, your account won't be permanently deleted until that audit activity expires.

    If you have any questions or don't want your account deleted, please contact #{admin()} as soon as possible.
    """)
  end

  def send_credential_deletion_notification_email(user, credential) do
    deliver(user.email, "Credential Deletion", """

    Hi #{user.first_name},

    Your "#{credential.name}" Credential has been scheduled for deletion.

    Here's what this means for you:

    - The credential has been disconnected from all projects. Nobody can use it.
    - Any jobs using this credential will now run without a credential. (If they require authentication, they may no longer function properly.)
    - After #{permanent_deletion_grace()} your credential’s secrets will be scrubbed. The record itself will be kept until all related audit trail activity has expired.

    You can cancel this deletion anytime before the scheduled date via the “Credentials” menu accessed by clicking opening the user menu in the top-right corner of the OpenFn interface.

    OpenFn

    """)
  end

  @doc """
  Deliver instructions to reset a user password.
  """
  def deliver_reset_password_instructions(user, url) do
    deliver(user.email, "Reset password instructions", """

    Hi #{user.email},

    You can reset your password by visiting the URL below:

    #{url}

    If you didn't request this change, please ignore this.
    """)
  end

  @doc """
  Deliver instructions to update a user email.
  """
  def deliver_update_email_instructions(user, url) do
    deliver(user.email, "Finish updating your email", """

    Hi #{user.first_name},

    We have received a request to change the email associated with your OpenFn account. To proceed, please visit the URL below:

    #{url}

    If you didn't request this change, please ignore this.

    OpenFn

    """)
  end

  @doc """
  Deliver warning to update a user email.
  """
  def deliver_update_email_warning(email, new_email) do
    deliver(email, "Update email warning", """

    Hi #{email},

    You have requested to change your email

    Please visit your inbox (#{new_email}) to activate your account

    If you didn't request this change, please ignore this.
    """)
  end

  def build_digest_url(workflow, start_date, end_date) do
    uri_params =
      SearchParams.to_uri_params(%{
        "date_after" => start_date,
        "date_before" => end_date,
        "workflow_id" => workflow.id
      })

    url(
      ~p"/projects/#{workflow.project_id}/history?#{%{"filters" => uri_params}}"
    )
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

  defp human_readable_grace_period(grace_period) do
    case grace_period do
      0 -> "today"
      1 -> "#{grace_period} day from today"
      _ -> "#{grace_period} days from today"
    end
  end

  def notify_project_deletion(%User{} = user, %Project{} = project) do
    grace_period = Lightning.Config.purge_deleted_after_days()

    deliver(user.email, "Project scheduled for deletion", """
    Hi #{user.first_name},

    Your OpenFn project “{#{project.name}” has been scheduled for deletion. All of the workflows in this project have been disabled, and its associated resources will be deleted in #{human_readable_grace_period(grace_period)} at {{actual_deletion_time – calculate based on the next 2am after the timestamp in the db?}}.

    If you don’t want this project deleted, please email support@openfn.org as soon as possible..

    OpenFn


    Your OpenFn project "#{project.name}" has been scheduled for deletion. All of the workflows in this project have been disabled,
    and the resources will be deleted in #{human_readable_grace_period(grace_period)} at 02:00 UTC. If this doesn't sound right, please email
    #{admin()} to cancel the deletion.
    """)
  end
end
