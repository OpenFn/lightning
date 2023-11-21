defmodule Lightning.FailureAlertTest do
  use LightningWeb.ChannelCase, async: true

  import Lightning.Factories
  import Lightning.Helpers, only: [ms_to_human: 1]
  import Swoosh.TestAssertions
  import ExUnit.Assertions

  alias Lightning.Repo
  alias Lightning.Workers
  alias Lightning.FailureAlerter

  describe "FailureAlert" do
    setup do
      period =
        Application.get_env(:lightning, Lightning.FailureAlerter)
        |> Keyword.get(:time_scale)
        |> ms_to_human()

      project =
        insert(:project,
          project_users: [%{user: build(:user), failure_alert: true}]
        )

      workflow_1 =
        insert(:workflow,
          name: "workflow-a",
          project: project
        )

      workorder_1 =
        insert(:workorder,
          workflow: workflow_1,
          trigger: build(:trigger),
          dataclip: build(:dataclip),
          last_activity: DateTime.utc_now()
        )

      attempt_1 =
        insert(:attempt,
          work_order: workorder_1,
          starting_trigger: build(:trigger),
          dataclip: build(:dataclip),
          finished_at: build(:timestamp),
          state: :started
        )
        |> Repo.preload(:log_lines)

      workflow_2 =
        insert(:workflow,
          name: "workflow-b",
          project: project
        )

      workorder_2 =
        insert(:workorder,
          workflow: workflow_2,
          trigger: build(:trigger),
          dataclip: build(:dataclip),
          last_activity: DateTime.utc_now()
        )

      attempt_2 =
        insert(:attempt,
          work_order: workorder_2,
          starting_trigger: build(:trigger),
          dataclip: build(:dataclip),
          finished_at: build(:timestamp)
        )
        |> Repo.preload(:log_lines)

      workflow_3 =
        insert(:workflow,
          name: "workflow-b",
          project:
            build(:project,
              project_users: [%{user: build(:user), failure_alert: false}]
            )
        )

      workorder_3 =
        insert(:workorder,
          workflow: workflow_3,
          trigger: build(:trigger),
          dataclip: build(:dataclip),
          last_activity: DateTime.utc_now()
        )

      attempt_3 =
        insert(:attempt,
          work_order: workorder_3,
          starting_trigger: build(:trigger),
          dataclip: build(:dataclip),
          finished_at: build(:timestamp)
        )
        |> Repo.preload(:log_lines)

      {:ok,
       period: period,
       project: project,
       workflows: [workflow_1, workflow_2, workflow_3],
       workorders: [workorder_1, workorder_2, workorder_3],
       attempts: [attempt_1, attempt_2, attempt_3]}
    end

    test "sends a limited number of failure alert emails to a subscribed user.",
         %{
           period: period,
           workorders: [workorder, _, _],
           attempts: [attempt, _, _]
         } do
      FailureAlerter.alert_on_failure(attempt)
      FailureAlerter.alert_on_failure(attempt)
      FailureAlerter.alert_on_failure(attempt)

      FailureAlerter.alert_on_failure(attempt)

      Oban.drain_queue(Oban, queue: :workflow_failures)

      # TODO: remove this with https://github.com/OpenFn/Lightning/issues/693
      Process.sleep(250)

      assert_receive {:email,
                      %Swoosh.Email{
                        subject: "\"workflow-a\" failed.",
                        html_body: html_body
                      }},
                     1000

      assert html_body =~ "workflow-a"
      assert html_body =~ workorder.id

      s2 = "\"workflow-a\" has failed 2 times in the last #{period}."
      assert_receive {:email, %Swoosh.Email{subject: ^s2}}, 1500

      s3 = "\"workflow-a\" has failed 3 times in the last #{period}."
      assert_receive {:email, %Swoosh.Email{subject: ^s3}}, 1500

      s4 = "\"workflow-a\" has failed 4 times in the last #{period}."
      refute_receive {:email, %Swoosh.Email{subject: ^s4}}, 250
    end

    test "sends a failure alert email for a workflow even if another workflow has been rate limited.",
         %{
           period: period,
           attempts: [attempt_1, attempt_2, _]
         } do
      FailureAlerter.alert_on_failure(attempt_1)
      FailureAlerter.alert_on_failure(attempt_1)
      FailureAlerter.alert_on_failure(attempt_1)

      FailureAlerter.alert_on_failure(attempt_2)

      Oban.drain_queue(Oban, queue: :workflow_failures)

      # TODO: remove this with https://github.com/OpenFn/Lightning/issues/693
      Process.sleep(250)

      assert_receive {:email, %Swoosh.Email{subject: "\"workflow-a\" failed."}},
                     1000

      s2 = "\"workflow-a\" has failed 2 times in the last #{period}."
      assert_receive {:email, %Swoosh.Email{subject: ^s2}}, 1500

      s3 = "\"workflow-a\" has failed 3 times in the last #{period}."
      assert_receive {:email, %Swoosh.Email{subject: ^s3}}, 1500

      assert_receive {:email, %Swoosh.Email{subject: "\"workflow-b\" failed."}},
                     1500
    end

    test "does not send failure emails to users who have unsubscribed", %{
      attempts: [attempt_1, _, attempt_3]
    } do
      FailureAlerter.alert_on_failure(attempt_1)

      assert_email_sent(subject: "\"workflow-a\" failed.")

      FailureAlerter.alert_on_failure(attempt_3)

      refute_email_sent(subject: "\"workflow-a\" failed.")
    end

    test "does not increment the rate-limiter counter when an email is not delivered.",
         %{attempts: [attempt, _, _], workorders: [workorder, _, _]} do
      [time_scale: time_scale, rate_limit: rate_limit] =
        Application.fetch_env!(:lightning, Lightning.FailureAlerter)

      FailureAlerter.alert_on_failure(attempt)

      {:ok, {0, ^rate_limit, _, _, _}} =
        Hammer.inspect_bucket(workorder.workflow_id, time_scale, rate_limit)

      assert_email_sent(subject: "\"workflow-a\" failed.")

      Mimic.stub(Lightning.FailureEmail, :deliver_failure_email, fn _, _ ->
        {:error}
      end)

      FailureAlerter.alert_on_failure(attempt)

      refute_email_sent(subject: "\"workflow-a\" failed.")

      # nothing changed
      {:ok, {0, ^rate_limit, _, _, _}} =
        Hammer.inspect_bucket(workorder.workflow_id, time_scale, rate_limit)
    end

    test "failure alert is sent on run complete", %{
      attempts: [attempt, _, _]
    } do
      Lightning.Stub.reset_time()

      {:ok, bearer, _} =
        Workers.Token.generate_and_sign(
          %{},
          Lightning.Config.worker_token_signer()
        )

      {:ok, %{}, socket} =
        LightningWeb.WorkerSocket
        |> socket("socket_id", %{token: bearer})
        |> subscribe_and_join(
          LightningWeb.AttemptChannel,
          "attempt:#{attempt.id}",
          %{"token" => Workers.generate_attempt_token(attempt)}
        )

      _ref =
        push(socket, "attempt:complete", %{
          "reason" => "crash",
          "error_type" => "RuntimeCrash",
          "error_message" => nil
        })

      assert_receive {:email, %Swoosh.Email{subject: "\"workflow-a\" failed."}},
                     1_000
    end
  end
end
