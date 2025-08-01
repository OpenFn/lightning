defmodule Lightning.Accounts.UserNotifierTest do
  use Lightning.DataCase, async: true
  use LightningWeb, :html

  import Mox
  import Swoosh.TestAssertions

  alias Lightning.Accounts.{UserNotifier, User}
  alias Lightning.DigestEmailWorker
  alias Lightning.Projects.Project
  alias Lightning.Credentials.Credential

  describe "Notification emails" do
    test "notify_project_deletion/2" do
      admin_email = Lightning.Config.instance_admin_email()

      user =
        Lightning.AccountsFixtures.user_fixture(
          email: "user@openfn.org",
          first_name: "User"
        )

      project = Lightning.ProjectsFixtures.project_fixture(name: "project-a")

      actual_deletion_date =
        Lightning.Config.purge_deleted_after_days()
        |> Lightning.Helpers.actual_deletion_date()
        |> Lightning.Helpers.format_date("%F at %T")

      UserNotifier.notify_project_deletion(user, project)

      assert_email_sent(
        subject: "Project scheduled for deletion",
        to: Swoosh.Email.Recipient.format(user),
        text_body: """
        Hi User,\n\nYour OpenFn project "project-a" has been scheduled for deletion.\n\nAll of the workflows in this project have been disabled, and it's associated resources will be deleted on #{actual_deletion_date}.\n\nIf you don't want this project deleted, please email #{admin_email} as soon as possible.\n\nOpenFn
        """
      )
    end

    test "deliver_project_addition_notification/2" do
      user = Lightning.AccountsFixtures.user_fixture(email: "user@openfn.org")

      project =
        Lightning.ProjectsFixtures.project_fixture(
          project_users: [%{user_id: user.id}]
        )

      url = LightningWeb.RouteHelpers.project_dashboard_url(project.id)

      UserNotifier.deliver_project_addition_notification(
        user,
        project
      )

      assert_email_sent(
        subject: "You now have access to \"#{project.name}\"",
        to: Swoosh.Email.Recipient.format(user),
        text_body: """
        Hi Anna,\n\nYou've been granted "editor" access to the "a-test-project" project on OpenFn.\n\nVisit the URL below to check it out:\n\n#{url}\n\nOpenFn
        """
      )
    end

    test "remind_account_confirmation/2" do
      token = "sometoken"

      UserNotifier.remind_account_confirmation(
        %User{
          email: "real@email.com",
          first_name: "Real"
        },
        token
      )

      url =
        LightningWeb.Router.Helpers.user_confirmation_url(
          LightningWeb.Endpoint,
          :edit,
          token
        )

      assert_email_sent(
        subject: "Confirm your OpenFn account",
        to: "real@email.com",
        text_body:
          "Hello Real,\n\nPlease confirm your OpenFn account by clicking on the URL below:\n\n#{url}\n\nIf you have not requested an account confirmation email, please ignore this.\n\nOpenFn\n"
      )
    end

    test "deliver_confirmation_instructions/2" do
      token = "sometoken"

      UserNotifier.deliver_confirmation_instructions(
        %User{
          email: "real@email.com"
        },
        token
      )

      url =
        LightningWeb.Router.Helpers.user_confirmation_url(
          LightningWeb.Endpoint,
          :edit,
          token
        )

      assert_email_sent(
        subject: "Confirm your OpenFn account",
        to: Swoosh.Email.Recipient.format(%User{email: "real@email.com"}),
        text_body:
          "Hi ,\n\nWelcome to OpenFn. Please confirm your account by visiting the URL below:\n\n#{url}\n\nIf you didn't create an account with us, please ignore this.\n\nOpenFn\n"
      )
    end

    test "deliver_confirmation_instructions/3" do
      token = "sometoken"

      enroller = %User{first_name: "Sizwe", email: "super@email.com"}

      user = %User{
        first_name: "Joe",
        email: "real@email.com"
      }

      UserNotifier.deliver_confirmation_instructions(
        enroller,
        user,
        token
      )

      url =
        LightningWeb.Router.Helpers.user_confirmation_url(
          LightningWeb.Endpoint,
          :edit,
          token
        )

      assert_email_sent(
        subject: "Confirm your OpenFn account",
        to: Swoosh.Email.Recipient.format(user),
        text_body: """
        Hi Joe,

        Sizwe has just created an OpenFn account for you. You can complete your registration by visiting the URL below:

        #{url}

        If you think this account was created by mistake, you can contact Sizwe (super@email.com) or ignore this email.

        OpenFn
        """
      )
    end

    test "send_deletion_notification_email/1" do
      user = build(:user)
      UserNotifier.send_deletion_notification_email(user)

      assert_email_sent(
        subject: "Your account has been scheduled for deletion",
        to: Swoosh.Email.Recipient.format(user)
      )
    end

    test "send_credential_deletion_notification_email/2" do
      UserNotifier.send_credential_deletion_notification_email(
        user = build(:user),
        %Credential{name: "Test"}
      )

      assert_email_sent(
        subject: "Your \"Test\" credential will be deleted",
        to: Swoosh.Email.Recipient.format(user)
      )
    end

    test "build_digest_url/3" do
      workflow = Lightning.WorkflowsFixtures.workflow_fixture(name: "Workflow A")
      start_date = Timex.now()
      end_date = Timex.now() |> Timex.shift(days: 2)

      digest_url = UserNotifier.build_digest_url(workflow, start_date, end_date)

      assert digest_url
             |> URI.decode_query(%{}, :rfc3986)
             |> Map.get("filters[date_after]") ==
               start_date |> DateTime.to_string() |> String.replace(" ", "+")

      assert digest_url
             |> URI.decode_query(%{}, :rfc3986)
             |> Map.get("filters[date_before]") ==
               end_date |> DateTime.to_string() |> String.replace(" ", "+")

      assert digest_url
             |> URI.decode_query(%{}, :rfc3986)
             |> Map.get("filters[workflow_id]") == workflow.id

      assert digest_url |> URI.parse() |> Map.get(:path) ==
               "/projects/#{workflow.project_id}/history"
    end

    test "Daily project digest email" do
      user = %User{email: "real@email.com", first_name: "Elias"}
      project = %Project{name: "Real Project"}

      workflow_a =
        Lightning.WorkflowsFixtures.workflow_fixture(name: "Workflow A")

      workflow_b =
        Lightning.WorkflowsFixtures.workflow_fixture(name: "Workflow B")

      workflow_c =
        Lightning.WorkflowsFixtures.workflow_fixture(name: "Workflow C")

      data = [
        %{
          workflow: workflow_a,
          successful_workorders: 12,
          rerun_workorders: 6,
          failed_workorders: 3
        },
        %{
          workflow: workflow_b,
          successful_workorders: 10,
          rerun_workorders: 0,
          failed_workorders: 0
        },
        %{
          workflow: workflow_c,
          successful_workorders: 3,
          rerun_workorders: 0,
          failed_workorders: 7
        }
      ]

      start_date = DigestEmailWorker.digest_to_date(:daily)
      end_date = Timex.now()

      UserNotifier.deliver_project_digest(data, %{
        user: user,
        project: project,
        digest: :daily,
        start_date: start_date,
        end_date: end_date
      })

      assert_email_sent(
        subject: "Daily digest for project Real Project",
        to: Swoosh.Email.Recipient.format(user),
        text_body: """
        Hi Elias,

        Here's your daily project digest for "Real Project", covering activity from #{start_date |> Lightning.Helpers.format_date_long()} to #{end_date |> Lightning.Helpers.format_date_long()}.

        Workflow A:
        - 12 workorders correctly processed today
        - 3 work orders that failed, crashed or timed out
        Click the link below to view this in the history page:
        #{UserNotifier.build_digest_url(workflow_a, start_date, end_date)}

        Workflow B:
        - 10 workorders correctly processed today
        - 0 work orders that failed, crashed or timed out
        Click the link below to view this in the history page:
        #{UserNotifier.build_digest_url(workflow_b, start_date, end_date)}

        Workflow C:
        - 3 workorders correctly processed today
        - 7 work orders that failed, crashed or timed out
        Click the link below to view this in the history page:
        #{UserNotifier.build_digest_url(workflow_c, start_date, end_date)}

        OpenFn
        """
      )
    end

    test "weekly project digest email" do
      user = %User{email: "real@email.com", first_name: "Elias"}
      project = %Project{name: "Real Project"}

      workflow_a =
        Lightning.WorkflowsFixtures.workflow_fixture(name: "Workflow A")

      workflow_b =
        Lightning.WorkflowsFixtures.workflow_fixture(name: "Workflow B")

      workflow_c =
        Lightning.WorkflowsFixtures.workflow_fixture(name: "Workflow C")

      data = [
        %{
          workflow: workflow_a,
          successful_workorders: 12,
          rerun_workorders: 6,
          failed_workorders: 3
        },
        %{
          workflow: workflow_b,
          successful_workorders: 10,
          rerun_workorders: 0,
          failed_workorders: 0
        },
        %{
          workflow: workflow_c,
          successful_workorders: 3,
          rerun_workorders: 0,
          failed_workorders: 7
        }
      ]

      start_date = DigestEmailWorker.digest_to_date(:weekly)
      end_date = Timex.now()

      UserNotifier.deliver_project_digest(data, %{
        user: user,
        project: project,
        digest: :weekly,
        start_date: start_date,
        end_date: end_date
      })

      assert_email_sent(
        subject: "Weekly digest for project Real Project",
        to: Swoosh.Email.Recipient.format(user),
        text_body: """
        Hi Elias,

        Here's your weekly project digest for "Real Project", covering activity from #{start_date |> Lightning.Helpers.format_date_long()} to #{end_date |> Lightning.Helpers.format_date_long()}.

        Workflow A:
        - 12 workorders correctly processed this week
        - 3 work orders that failed, crashed or timed out
        Click the link below to view this in the history page:
        #{UserNotifier.build_digest_url(workflow_a, start_date, end_date)}

        Workflow B:
        - 10 workorders correctly processed this week
        - 0 work orders that failed, crashed or timed out
        Click the link below to view this in the history page:
        #{UserNotifier.build_digest_url(workflow_b, start_date, end_date)}

        Workflow C:
        - 3 workorders correctly processed this week
        - 7 work orders that failed, crashed or timed out
        Click the link below to view this in the history page:
        #{UserNotifier.build_digest_url(workflow_c, start_date, end_date)}

        OpenFn
        """
      )
    end

    test "Monthly project digest email" do
      user = %User{email: "real@email.com", first_name: "Elias"}
      project = %Project{name: "Real Project"}

      workflow_a =
        Lightning.WorkflowsFixtures.workflow_fixture(name: "Workflow A")

      workflow_b =
        Lightning.WorkflowsFixtures.workflow_fixture(name: "Workflow B")

      workflow_c =
        Lightning.WorkflowsFixtures.workflow_fixture(name: "Workflow C")

      data = [
        %{
          workflow: workflow_a,
          successful_workorders: 12,
          rerun_workorders: 6,
          failed_workorders: 3
        },
        %{
          workflow: workflow_b,
          successful_workorders: 10,
          rerun_workorders: 0,
          failed_workorders: 0
        },
        %{
          workflow: workflow_c,
          successful_workorders: 3,
          rerun_workorders: 0,
          failed_workorders: 7
        }
      ]

      digest_type = :monthly

      start_date = DigestEmailWorker.digest_to_date(digest_type)
      end_date = Timex.now()

      UserNotifier.deliver_project_digest(data, %{
        user: user,
        project: project,
        digest: digest_type,
        start_date: start_date,
        end_date: end_date
      })

      assert_email_sent(
        subject: "Monthly digest for project Real Project",
        to: Swoosh.Email.Recipient.format(user),
        text_body: """
        Hi Elias,

        Here's your monthly project digest for "Real Project", covering activity from #{start_date |> Lightning.Helpers.format_date_long()} to #{end_date |> Lightning.Helpers.format_date_long()}.

        Workflow A:
        - 12 workorders correctly processed this month
        - 3 work orders that failed, crashed or timed out
        Click the link below to view this in the history page:
        #{UserNotifier.build_digest_url(workflow_a, start_date, end_date)}

        Workflow B:
        - 10 workorders correctly processed this month
        - 0 work orders that failed, crashed or timed out
        Click the link below to view this in the history page:
        #{UserNotifier.build_digest_url(workflow_b, start_date, end_date)}

        Workflow C:
        - 3 workorders correctly processed this month
        - 7 work orders that failed, crashed or timed out
        Click the link below to view this in the history page:
        #{UserNotifier.build_digest_url(workflow_c, start_date, end_date)}

        OpenFn
        """
      )
    end

    test "digest emails with no activity" do
      user = %User{email: "real@email.com", first_name: "Elias"}
      project = %Project{name: "Real Project"}
      workflow = Lightning.WorkflowsFixtures.workflow_fixture(name: "Workflow A")

      data = [
        %{
          workflow: workflow,
          successful_workorders: 0,
          rerun_workorders: 0,
          failed_workorders: 0
        }
      ]

      for digest_type <- [:daily, :weekly, :monthly] do
        period =
          case digest_type do
            :daily -> "today"
            :weekly -> "this week"
            :monthly -> "this month"
          end

        start_date = DigestEmailWorker.digest_to_date(digest_type)
        end_date = Timex.now()

        UserNotifier.deliver_project_digest(data, %{
          user: user,
          project: project,
          digest: digest_type,
          start_date: start_date,
          end_date: end_date
        })

        assert_email_sent(
          subject:
            "#{String.capitalize("#{digest_type}")} digest for project Real Project",
          to: Swoosh.Email.Recipient.format(user),
          text_body: """
          Hi Elias,

          Here's your #{digest_type} project digest for "Real Project", covering activity from #{start_date |> Lightning.Helpers.format_date_long()} to #{end_date |> Lightning.Helpers.format_date_long()}.

          Workflow A:
          - 0 workorders correctly processed #{period}
          - 0 work orders that failed, crashed or timed out
          Click the link below to view this in the history page:
          #{UserNotifier.build_digest_url(workflow, start_date, end_date)}

          OpenFn
          """
        )
      end
    end

    test "Kafka trigger failure - alternate storage disabled" do
      stub(Lightning.MockConfig, :kafka_alternate_storage_enabled?, fn ->
        false
      end)

      timestamp = DateTime.utc_now()

      displayed_timestamp =
        timestamp
        |> DateTime.truncate(:second)
        |> DateTime.to_iso8601()

      user = Lightning.AccountsFixtures.user_fixture()
      workflow = insert(:workflow)

      workflow_url =
        LightningWeb.Endpoint
        |> url(~p"/projects/#{workflow.project_id}/w/#{workflow.id}")

      UserNotifier.send_trigger_failure_mail(user, workflow, timestamp)

      assert_email_sent(
        subject: "Kafka trigger failure on #{workflow.name}",
        to: Swoosh.Email.Recipient.format(user),
        text_body: """
        As of #{displayed_timestamp}, the Kafka trigger associated with the workflow `#{workflow.name}` (#{workflow_url}) has failed to persist at least one message.

        THIS LIGHTNING INSTANCE DOES NOT HAVE ALTERNATE STORAGE ENABLED, SO THESE FAILED MESSAGES CANNOT BE RECOVERED WITHOUT MAKING THEM AVAILABLE ON THE KAFKA CLUSTER AGAIN.

        If you have access to the system logs, please look for entries containing 'Kafka Pipeline Error'.

        OpenFn
        """
      )
    end

    test "Kafka trigger failure - alternate storage enabled" do
      stub(Lightning.MockConfig, :kafka_alternate_storage_enabled?, fn ->
        true
      end)

      timestamp = DateTime.utc_now()

      displayed_timestamp =
        timestamp
        |> DateTime.truncate(:second)
        |> DateTime.to_iso8601()

      user = Lightning.AccountsFixtures.user_fixture()
      workflow = insert(:workflow)

      workflow_url =
        LightningWeb.Endpoint
        |> url(~p"/projects/#{workflow.project_id}/w/#{workflow.id}")

      UserNotifier.send_trigger_failure_mail(user, workflow, timestamp)

      assert_email_sent(
        subject: "Kafka trigger failure on #{workflow.name}",
        to: Swoosh.Email.Recipient.format(user),
        text_body: """
        As of #{displayed_timestamp}, the Kafka trigger associated with the workflow `#{workflow.name}` (#{workflow_url}) has failed to persist at least one message.

        This Lightning instance has alternate storage enabled. This means that any messages that failed to persist will be stored in the location referenced by the KAFKA_ALTERNATE_STORAGE_FILE_PATH environment variable. These messages can be recovered by reprocessing them.

        If you have access to the system logs, please look for entries containing 'Kafka Pipeline Error'.

        OpenFn
        """
      )
    end
  end
end
