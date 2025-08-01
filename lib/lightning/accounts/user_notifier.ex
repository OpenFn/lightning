defmodule Lightning.Accounts.UserNotifier do
  @moduledoc """
  The UserNotifier module.
  """

  use LightningWeb, :html

  use Oban.Worker,
    queue: :background,
    max_attempts: 1

  import Swoosh.Email
  import LightningWeb.Utils, only: [pluralize_with_s: 2]

  alias Lightning.Accounts.User
  alias Lightning.Helpers
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
    deliver(user, "Confirm your OpenFn account", """
    Hi #{user.first_name},

    Welcome to OpenFn. Please confirm your account by visiting the URL below:

    #{url(~p"/users/confirm/#{token}")}

    If you didn't create an account with us, please ignore this.

    OpenFn
    """)
  end

  @doc """
  Deliver instructions to confirm account.
  """
  def deliver_confirmation_instructions(enroller, user, token) do
    deliver(user, "Confirm your OpenFn account", """
    Hi #{user.first_name},

    #{enroller.first_name} has just created an OpenFn account for you. You can complete your registration by visiting the URL below:

    #{url(~p"/users/confirm/#{token}")}

    If you think this account was created by mistake, you can contact #{enroller.first_name} (#{enroller.email}) or ignore this email.

    OpenFn
    """)
  end

  def remind_account_confirmation(user, token) do
    deliver(user.email, "Confirm your OpenFn account", """
    Hello #{user.first_name},

    Please confirm your OpenFn account by clicking on the URL below:

    #{url(~p"/users/confirm/#{token}")}

    If you have not requested an account confirmation email, please ignore this.

    OpenFn
    """)
  end

  @doc """
  Deliver email to notify user of his addition of a project.
  """
  def deliver_project_addition_notification(user, project) do
    role = Projects.get_project_user_role(user, project) |> Atom.to_string()

    deliver(user, "You now have access to \"#{project.name}\"", """
    Hi #{user.first_name},

    You've been granted "#{role}" access to the "#{project.name}" project on OpenFn.

    Visit the URL below to check it out:

    #{url(~p"/projects/#{project}/w")}

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
    history_retention_period = updated_project.history_retention_period || "∞"

    io_data_retention_period =
      updated_project.dataclip_retention_period || history_retention_period

    io_data_saved = updated_project.retention_policy != :erase_all

    deliver(
      user,
      "The data retention policy for #{updated_project.name} has been modified",
      """
      Hi #{user.first_name},

      The data retention policy for your project, #{updated_project.name}, has been updated. Here are the new details:

      - #{history_retention_period} #{pluralize_with_s(history_retention_period, "day")} history retention
      - input/output (I/O) data #{if io_data_saved, do: "is", else: "is not"} saved for reprocessing
      - #{io_data_retention_period} #{pluralize_with_s(io_data_retention_period, "day")} I/O data retention

      This policy can be changed by owners and administrators. If you haven't approved this change, please reset the policy by visiting the URL below:

      #{url(~p"/projects/#{updated_project.id}/settings#data-storage")}

      OpenFn
      """
    )
  end

  @doc """
  Deliver an email to notify the user about their account being deleted
  """
  def send_deletion_notification_email(user) do
    actual_deletion_date =
      Lightning.Config.purge_deleted_after_days()
      |> Lightning.Helpers.actual_deletion_date()
      |> Lightning.Helpers.format_date()

    deliver(user, "Your account has been scheduled for deletion", """
     Hi #{user.first_name},

    Your OpenFn account has been scheduled for deletion. It has been disabled and you'll no longer be able to log in.

    Your account and of your credentials will be permanently deleted on #{actual_deletion_date} and you'll be removed from all projects you're currently a collaborator on.

    Please note that if you have auditable events associated with projects, your account won't be permanently deleted until that audit activity expires.

    If you have any questions or don't want your account deleted, please contact #{admin()} as soon as possible.

    OpenFn
    """)
  end

  def send_credential_deletion_notification_email(user, credential) do
    deliver(
      user,
      "Your \"#{credential.name}\" credential will be deleted",
      """
      Hi #{user.first_name},

      Your "#{credential.name}" credential has been scheduled for deletion.

      Here's what this means for you:

      - The credential has been disconnected from all projects. Nobody can use it.
      - Any jobs using this credential will now run without a credential. (If they require authentication, they may no longer function properly.)
      - After #{permanent_deletion_grace()} your credential's secrets will be scrubbed. The record itself will be kept until all related audit trail activity has expired.

      You can cancel this deletion anytime before the scheduled date via the "Credentials" menu accessed by clicking opening the user menu in the top-right corner of the OpenFn interface.

      OpenFn
      """
    )
  end

  @doc """
  Deliver instructions to reset a user password.
  """
  def deliver_reset_password_instructions(user, url) do
    deliver(user, "Finish resetting your password", """
    Hi #{user.first_name},

    We have received a request to reset your OpenFn password.

    To proceed, please visit the URL below:

    #{url}

    Note that this link is only valid for #{Lightning.Config.reset_password_token_validity_in_days()} #{pluralize_with_s(Lightning.Config.reset_password_token_validity_in_days(), "day")}. If you didn't request this change, please ignore this.

    OpenFn
    """)
  end

  @doc """
  Deliver instructions to update a user.
  """
  def deliver_update_email_instructions(user, token) do
    deliver(user, "Please confirm your new email", """
    Hi #{user.first_name},

    We have received a request to change the email associated with your OpenFn account.

    To proceed, please visit the URL below:

    #{url(~p"/profile/confirm_email/#{token}")}

    If you didn't request this change, please ignore this.

    OpenFn
    """)
  end

  @doc """
  Deliver warning to update a user.
  """
  def deliver_update_email_warning(user, new_email) do
    deliver(user, "Your OpenFn email was changed", """
    Hi #{user.first_name},

    We have received a request to change the email address associated with your OpenFn account from #{user.email} to #{new_email}.

    An email has been sent to your new email address with a confirmation link.

    If you didn't request this change, please contact #{admin()} immediately to regain control of your account. When your account has been secured, we'd also recommend that you turn on multi-factor authentication to prevent further unauthorized access.

    OpenFn
    """)
  end

  def notify_history_export_completion(user, project_file) do
    deliver(user, "Your OpenFn History Export Is Complete", """
    Hello #{user.first_name},

    You history export requested on #{Helpers.format_date(project_file.inserted_at, "%F at %T")} is completed. Please visit this URL to download the file:

    #{url(~p"/project_files/#{project_file.id}/download")}

    OpenFn
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
      "#{String.capitalize(Atom.to_string(digest))} digest for project #{project.name}"

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
      |> String.trim()

    body = """
    Hi #{user.first_name},

    Here's your #{Atom.to_string(digest)} project digest for "#{project.name}", covering activity from #{start_date |> Lightning.Helpers.format_date_long()} to #{end_date |> Lightning.Helpers.format_date_long()}.

    #{body}

    OpenFn
    """

    deliver(user, title, body)
  end

  def notify_project_deletion(
        %User{} = user,
        %Project{} = project
      ) do
    actual_deletion_date =
      Lightning.Config.purge_deleted_after_days()
      |> Lightning.Helpers.actual_deletion_date()
      |> Lightning.Helpers.format_date("%F at %T")

    deliver(user, "Project scheduled for deletion", """
    Hi #{user.first_name},

    Your OpenFn project "#{project.name}" has been scheduled for deletion.

    All of the workflows in this project have been disabled, and it's associated resources will be deleted on #{actual_deletion_date}.

    If you don't want this project deleted, please email #{admin()} as soon as possible.

    OpenFn
    """)
  end

  def deliver_project_invitation_email(user, inviter, project, role, token) do
    deliver(user, "Join #{project.name} on OpenFn as a collaborator", """
    Hi #{user.first_name},

    #{inviter.first_name} has invited you to join project "#{project.name}" and granted you "#{role}" access. Since you don't have an OpenFn account yet, we've set one up for you.

    Please click the link below to complete your account setup: #{url(~p"/users/reset_password/#{token}")}

    If you did not request to join this project, please ignore this email.

    OpenFn
    """)
  end

  def send_trigger_failure_mail(user, workflow, timestamp) do
    display_timestamp =
      timestamp |> DateTime.truncate(:second) |> DateTime.to_iso8601()

    deliver(user, "Kafka trigger failure on #{workflow.name}", """
    As of #{display_timestamp}, the Kafka trigger associated with the workflow `#{workflow.name}` (#{url(~p"/projects/#{workflow.project_id}/w/#{workflow.id}")}) has failed to persist at least one message.

    #{alternate_storage_message(Lightning.Config.kafka_alternate_storage_enabled?())}

    If you have access to the system logs, please look for entries containing 'Kafka Pipeline Error'.

    OpenFn
    """)
  end

  defp alternate_storage_message(true = _alternate_storage_enabled) do
    "This Lightning instance has alternate storage enabled. This means that any messages that failed to persist will be stored in the location referenced by the KAFKA_ALTERNATE_STORAGE_FILE_PATH environment variable. These messages can be recovered by reprocessing them."
  end

  defp alternate_storage_message(false = _alternate_storage_enabled) do
    "THIS LIGHTNING INSTANCE DOES NOT HAVE ALTERNATE STORAGE ENABLED, SO THESE FAILED MESSAGES CANNOT BE RECOVERED WITHOUT MAKING THEM AVAILABLE ON THE KAFKA CLUSTER AGAIN."
  end

  @doc """
  Deliver instructions to confirm a credential transfer.
  """
  def deliver_credential_transfer_confirmation_instructions(
        owner,
        receiver,
        credential,
        token
      ) do
    validity_text =
      Lightning.Config.credential_transfer_token_validity_in_days()
      |> format_validity_period()

    confirmation_url =
      url(~p"/credentials/transfer/#{credential.id}/#{receiver.id}/#{token}")

    deliver(owner, "Transfer #{credential.name} to #{receiver.first_name}", """
    Hi #{owner.first_name},

    You are about to transfer #{credential.name} to #{receiver.first_name} (#{receiver.email}). Please ignore this email if you have not requested to transfer this credential.

    To confirm this activity, click the link below:

    #{confirmation_url}

    Please note:
    1. Transferring your credentials is irreversible and can impact the security of your projects.
    2. This link is only valid for #{validity_text}.

    OpenFn
    """)
  end

  defp format_validity_period(days) do
    "#{days} #{pluralize_with_s(days, "day")}"
  end

  def deliver_credential_transfer_notification(
        receiver,
        owner,
        credential
      ) do
    credentials_url = url(~p"/credentials")

    deliver(receiver, "A credential has been transferred to you.", """
    #{owner.first_name} has transferred the credential \"#{credential.name}\" to you. As a credential owner, you can edit the credential details and share the credential with other projects in your OpenFn account.

    See your credential list here: #{credentials_url}

    OpenFn
    """)
  end
end
