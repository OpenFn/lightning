defmodule Lightning.FailureAlertTest do
  use LightningWeb.ChannelCase, async: true

  import Lightning.ApplicationHelpers, only: [capture_info_log: 1]
  import Lightning.Factories
  import Lightning.Helpers, only: [ms_to_human: 1]
  import Lightning.TokenHelpers
  import Swoosh.TestAssertions

  alias Lightning.Extensions.UsageLimiter
  alias Lightning.Extensions.UsageLimiting.Context
  alias Lightning.FailureAlerter
  alias Lightning.Repo
  alias Lightning.Workers

  setup do
    Mox.stub(Lightning.Extensions.MockUsageLimiter, :check_limits, fn _context ->
      :ok
    end)

    Mox.stub(
      Lightning.Extensions.MockUsageLimiter,
      :limit_action,
      fn _action, _context ->
        :ok
      end
    )

    :ok
  end

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

      run_1 =
        insert(:run,
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

      run_2 =
        insert(:run,
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

      run_3 =
        insert(:run,
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
       runs: [run_1, run_2, run_3]}
    end

    test "sends a limited number of failure alert emails to a subscribed user.",
         %{
           period: period,
           workorders: [workorder, _, _],
           runs: [run, _, _],
           project: project
         } do
      FailureAlerter.alert_on_failure(run)
      FailureAlerter.alert_on_failure(run)
      FailureAlerter.alert_on_failure(run)

      FailureAlerter.alert_on_failure(run)

      Oban.drain_queue(Lightning.Oban, queue: :workflow_failures)

      # TODO: remove this with https://github.com/OpenFn/Lightning/issues/693
      Process.sleep(250)

      s1 = "\"workflow-a\" (#{project.name}) failed"

      assert_receive {:email,
                      %Swoosh.Email{
                        subject: ^s1,
                        html_body: html_body
                      }},
                     1000

      assert html_body =~ "workflow-a"
      assert html_body =~ workorder.id

      assert html_body =~
               "A \"#{workorder.workflow.name}\" run just failed in \"#{workorder.workflow.project.name}\""

      s2 =
        "\"workflow-a\" (#{project.name}) failed 2 times in the last #{period}"

      assert_receive {:email, %Swoosh.Email{subject: ^s2}}, 1500

      s3 =
        "\"workflow-a\" (#{project.name}) failed 3 times in the last #{period}"

      assert_receive {:email, %Swoosh.Email{subject: ^s3}}, 1500

      s4 =
        "\"workflow-a\" (#{project.name}) failed 4 times in the last #{period}"

      refute_receive {:email, %Swoosh.Email{subject: ^s4}}, 250
    end

    test "sends a failure alert email for a workflow even if another workflow has been rate limited.",
         %{
           period: period,
           runs: [run_1, run_2, _],
           project: project
         } do
      FailureAlerter.alert_on_failure(run_1)
      FailureAlerter.alert_on_failure(run_1)
      FailureAlerter.alert_on_failure(run_1)

      FailureAlerter.alert_on_failure(run_2)

      Oban.drain_queue(Lightning.Oban, queue: :workflow_failures)

      # TODO: remove this with https://github.com/OpenFn/Lightning/issues/693
      Process.sleep(250)

      s1 = "\"workflow-a\" (#{project.name}) failed"

      assert_receive {:email, %Swoosh.Email{subject: ^s1}}, 1000

      s2 =
        "\"workflow-a\" (#{project.name}) failed 2 times in the last #{period}"

      assert_receive {:email, %Swoosh.Email{subject: ^s2}}, 1500

      s3 =
        "\"workflow-a\" (#{project.name}) failed 3 times in the last #{period}"

      assert_receive {:email, %Swoosh.Email{subject: ^s3}}, 1500

      s4 = "\"workflow-b\" (#{project.name}) failed"

      assert_receive {:email, %Swoosh.Email{subject: ^s4}}, 1500
    end

    test "does not send failure emails to users who have unsubscribed", %{
      runs: [run_1, _, run_3],
      project: project
    } do
      FailureAlerter.alert_on_failure(run_1)

      s1 = "\"workflow-a\" (#{project.name}) failed"
      assert_receive {:email, %Swoosh.Email{subject: ^s1}}, 1500

      FailureAlerter.alert_on_failure(run_3)

      s3 = "\"workflow-a\" (#{project.name}) failed"
      refute_email_sent(subject: ^s3)
    end

    test "does not send failure emails if the usage limiter returns an error", %{
      runs: [run_1 | _rest],
      project: %{id: project_id, name: project_name}
    } do
      Mox.expect(
        Lightning.Extensions.MockUsageLimiter,
        :limit_action,
        fn %{type: :alert_failure}, %{project_id: ^project_id} ->
          :ok
        end
      )

      FailureAlerter.alert_on_failure(run_1)

      assert_email_sent(subject: "\"workflow-a\" (#{project_name}) failed")

      Mox.expect(
        Lightning.Extensions.MockUsageLimiter,
        :limit_action,
        fn %{type: :alert_failure}, %{project_id: ^project_id} ->
          {:error, :not_enabled, %{text: "Failure alerts not enabled"}}
        end
      )

      FailureAlerter.alert_on_failure(run_1)

      s1 = "\"workflow-a\" (#{project_name}) failed"
      refute_email_sent(subject: ^s1)
    end

    test "does not increment the rate-limiter counter when an email is not delivered.",
         %{runs: [run, _, _], workorders: [workorder, _, _], project: project} do
      [time_scale: time_scale, rate_limit: rate_limit] =
        Application.fetch_env!(:lightning, Lightning.FailureAlerter)

      FailureAlerter.alert_on_failure(run)

      {:ok, {0, ^rate_limit, _, _, _}} =
        Hammer.inspect_bucket(workorder.workflow_id, time_scale, rate_limit)

      assert_email_sent(subject: "\"workflow-a\" (#{project.name}) failed")

      Mimic.stub(Lightning.FailureEmail, :deliver_failure_email, fn _, _ ->
        {:error}
      end)

      FailureAlerter.alert_on_failure(run)

      subject = "\"workflow-a\" (#{project.name}) failed"
      refute_email_sent(subject: ^subject)

      # nothing changed
      {:ok, {0, ^rate_limit, _, _, _}} =
        Hammer.inspect_bucket(workorder.workflow_id, time_scale, rate_limit)
    end

    test "failure alert is sent on run complete", %{
      runs: [run, _, _],
      project: project
    } do
      Lightning.Stub.reset_time()

      # `socket/3` bypasses `WorkerSocket.connect/2`, so these claims are
      # assigned rather than verified — but they are still the shape ws-worker sends.
      claims = ws_worker_claims()

      expect(Lightning.MockConfig, :default_max_run_duration, fn -> 1 end)

      run_options =
        UsageLimiter.get_run_options(%Context{
          project_id: run.work_order.workflow.project_id
        })
        |> Map.new()

      {:ok, %{}, socket} =
        LightningWeb.WorkerSocket
        |> socket("socket_id", %{token: raw_worker_token(claims), claims: claims})
        |> subscribe_and_join(
          LightningWeb.RunChannel,
          "run:#{run.id}",
          %{
            "token" => Workers.generate_run_token(run, run_options)
          }
        )

      _ref =
        push(socket, "run:complete", %{
          "reason" => "crash",
          "error_type" => "RuntimeCrash",
          "error_message" => nil
        })

      subject = "\"workflow-a\" (#{project.name}) failed"

      assert_receive {:email, %Swoosh.Email{subject: ^subject}},
                     1_000
    end
  end

  describe "recipients who may not be sent the project's contents" do
    test "an enrolled member of a project that requires MFA is still alerted" do
      user = insert(:user, mfa_enabled: true)

      project =
        insert(:project,
          requires_mfa: true,
          project_users: [%{user_id: user.id, failure_alert: true}]
        )

      run = failing_run(project, "workflow-enrolled")

      FailureAlerter.alert_on_failure(run)

      recipient = [{"", user.email}]
      subject = "\"workflow-enrolled\" (#{project.name}) failed"

      assert_received {:email, %Swoosh.Email{to: ^recipient, subject: ^subject}}
    end

    test "a disabled account is not alerted" do
      user = insert(:user, disabled: true)

      project =
        insert(:project,
          project_users: [%{user_id: user.id, failure_alert: true}]
        )

      FailureAlerter.alert_on_failure(failing_run(project, "workflow-disabled"))

      recipient = [{"", user.email}]
      refute_received {:email, %Swoosh.Email{to: ^recipient}}
    end

    test "an account scheduled for deletion is not alerted" do
      user = insert(:user, scheduled_deletion: DateTime.utc_now())

      project =
        insert(:project,
          project_users: [%{user_id: user.id, failure_alert: true}]
        )

      FailureAlerter.alert_on_failure(failing_run(project, "workflow-leaving"))

      recipient = [{"", user.email}]
      refute_received {:email, %Swoosh.Email{to: ^recipient}}
    end

    test "a member who has not enrolled in MFA is not alerted for a project that requires it" do
      user = insert(:user, mfa_enabled: false)

      project =
        insert(:project,
          requires_mfa: true,
          project_users: [%{user_id: user.id, failure_alert: true}]
        )

      FailureAlerter.alert_on_failure(failing_run(project, "workflow-mfa"))

      recipient = [{"", user.email}]
      refute_received {:email, %Swoosh.Email{to: ^recipient}}
    end

    test "a refused recipient spends none of the workflow's rate-limit budget" do
      [time_scale: time_scale, rate_limit: rate_limit] =
        Application.fetch_env!(:lightning, Lightning.FailureAlerter)

      disabled_user = insert(:user, disabled: true)
      live_user = insert(:user)

      project =
        insert(:project,
          project_users: [
            %{user_id: disabled_user.id, failure_alert: true},
            %{user_id: live_user.id, failure_alert: true}
          ]
        )

      run = failing_run(project, "workflow-budget")
      workflow_id = run.work_order.workflow.id

      for _ <- 1..rate_limit, do: FailureAlerter.alert_on_failure(run)

      # The refused recipient never reached the rate limiter, so their bucket
      # was never created.
      assert {:ok, {0, ^rate_limit, _ms, nil, nil}} =
               Hammer.inspect_bucket(
                 "#{workflow_id}::#{disabled_user.id}",
                 time_scale,
                 rate_limit
               )

      live_recipient = [{"", live_user.email}]

      for _ <- 1..rate_limit do
        assert_received {:email, %Swoosh.Email{to: ^live_recipient}}
      end

      refused_recipient = [{"", disabled_user.email}]
      refute_received {:email, %Swoosh.Email{to: ^refused_recipient}}
    end

    # The verification deadline is the one condition that turns on a config
    # flag rather than on the records, so it is worth pinning on a real send.
    test "an account barred pending email confirmation is not alerted" do
      Mox.stub(Lightning.MockConfig, :check_flag?, fn
        :require_email_verification -> true
        other -> Lightning.Config.API.check_flag?(other)
      end)

      user =
        insert(:user,
          confirmed_at: nil,
          inserted_at: DateTime.utc_now(:second) |> DateTime.add(-50, :hour)
        )

      project =
        insert(:project,
          project_users: [%{user_id: user.id, failure_alert: true}]
        )

      FailureAlerter.alert_on_failure(
        failing_run(project, "workflow-unconfirmed")
      )

      recipient = [{"", user.email}]
      refute_received {:email, %Swoosh.Email{to: ^recipient}}
    end

    # Without this line, "I never got the alert" leaves the same evidence as a
    # mailer outage. `info`, not `error`: a refusal is the rule working.
    test "records the withheld alert in the log" do
      user = insert(:user, disabled: true)

      project =
        insert(:project,
          project_users: [%{user_id: user.id, failure_alert: true}]
        )

      run = failing_run(project, "workflow-logged")

      {_result, log} =
        capture_info_log(fn -> FailureAlerter.alert_on_failure(run) end)

      assert log =~ "Withheld failure alert from user #{user.id}"
      assert log =~ "in project #{project.id}"

      # The address itself stays out of the log; the ids are enough to answer
      # "why did this person not get mail".
      refute log =~ user.email
    end

    # The alerter loads its project with `get_project!/1`, which has no
    # liveness filter of its own. The refusal comes from the recipient rule.
    test "no one is alerted for a project that is winding down" do
      user = insert(:user)

      project =
        insert(:project,
          scheduled_deletion: DateTime.utc_now() |> DateTime.truncate(:second),
          project_users: [%{user_id: user.id, failure_alert: true}]
        )

      FailureAlerter.alert_on_failure(failing_run(project, "workflow-closing"))

      recipient = [{"", user.email}]
      refute_received {:email, %Swoosh.Email{to: ^recipient}}
    end
  end

  defp failing_run(project, workflow_name) do
    workflow = insert(:workflow, name: workflow_name, project: project)

    workorder =
      insert(:workorder,
        workflow: workflow,
        trigger: build(:trigger),
        dataclip: build(:dataclip),
        last_activity: DateTime.utc_now()
      )

    insert(:run,
      work_order: workorder,
      starting_trigger: build(:trigger),
      dataclip: build(:dataclip),
      finished_at: build(:timestamp),
      state: :started
    )
    |> Repo.preload(:log_lines)
  end
end
