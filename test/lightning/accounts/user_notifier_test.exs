defmodule Lightning.Accounts.UserNotifierTest do
  use Lightning.DataCase, async: true
  use LightningWeb, :html

  import Swoosh.TestAssertions

  alias Lightning.DigestEmailWorker
  alias Lightning.Accounts.{UserNotifier, User}
  alias Lightning.Projects.Project
  alias Lightning.Credentials.Credential

  describe "Notification emails" do
    test "notify_project_deletion/2" do
      admin_email =
        Application.get_env(:lightning, :email_addresses) |> Keyword.get(:admin)

      user =
        Lightning.AccountsFixtures.user_fixture(
          email: "user@openfn.org",
          first_name: "User"
        )

      project = Lightning.ProjectsFixtures.project_fixture(name: "project-a")

      UserNotifier.notify_project_deletion(user, project)

      assert_email_sent(
        subject: "Project scheduled for deletion",
        to: "user@openfn.org",
        text_body:
          "Hi User,\n\nproject-a project has been scheduled for deletion. All of the workflows in this project have been disabled,\nand the resources will be deleted in 7 day(s) from today at 02:00 UTC. If this doesn't sound right, please email\n#{admin_email} to cancel the deletion.\n"
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
        subject: "Project #{project.name}",
        to: "user@openfn.org",
        text_body:
          "\nHi Anna,\n\nYou've been added to the project \"a-test-project\" as an editor.\n\nClick the link below to check it out:\n\n#{url}\n\n"
      )
    end

    test "deliver_confirmation_instructions/2" do
      UserNotifier.deliver_confirmation_instructions(
        %User{
          email: "real@email.com"
        },
        "https://lightning/users/confirm/token"
      )

      assert_email_sent(
        subject: "Confirmation instructions",
        to: "real@email.com",
        text_body:
          "\nHi ,\n\nWelcome and thanks for registering a new account on OpenFn/Lightning. Please confirm your account by visiting the URL below:\n\nhttps://lightning/users/confirm/token.\n\nIf you didn't create an account with us, please ignore this.\n\n"
      )
    end

    test "deliver_confirmation_instructions/3" do
      UserNotifier.deliver_confirmation_instructions(
        %User{first_name: "Super User", email: "super@email.com"},
        %User{
          first_name: "Joe",
          email: "real@email.com"
        },
        "https://lightning/users/confirm/token"
      )

      assert_email_sent(
        subject: "New OpenFn Lightning account",
        to: "real@email.com",
        text_body:
          "\nHi Joe,\n\nSuper User has just created an account for you on OpenFn/Lightning. You can complete your registration by visiting the URL below:\n\nhttps://lightning/users/confirm/token.\n\nIf you do not wish to have an account, please ignore this email.\n\n"
      )
    end

    test "send_deletion_notification_email/1" do
      UserNotifier.send_deletion_notification_email(%User{
        email: "real@email.com"
      })

      assert_email_sent(
        subject: "Lightning Account Deletion",
        to: "real@email.com"
      )
    end

    test "send_credential_deletion_notification_email/2" do
      UserNotifier.send_credential_deletion_notification_email(
        %User{
          email: "real@email.com"
        },
        %Credential{name: "Test"}
      )

      assert_email_sent(
        subject: "Credential Deletion",
        to: "real@email.com"
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
        to: "real@email.com",
        text_body: """
        Hi Elias,

        Here's a daily digest for "Real Project" project activity since #{start_date |> Calendar.strftime("%a %B %d %Y at %H:%M %Z")}.

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
        to: "real@email.com",
        text_body: """
        Hi Elias,

        Here's a weekly digest for "Real Project" project activity since #{start_date |> Calendar.strftime("%a %B %d %Y at %H:%M %Z")}.

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
        to: "real@email.com",
        text_body: """
        Hi Elias,

        Here's a monthly digest for "Real Project" project activity since #{start_date |> Calendar.strftime("%a %B %d %Y at %H:%M %Z")}.

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


        """
      )
    end
  end
end
