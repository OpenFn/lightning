defmodule Lightning.FailureAlertTest do
  use Lightning.DataCase, async: true
  use Mimic

  alias Lightning.Pipeline
  alias Lightning.{Attempt, AttemptRun}
  alias Lightning.Invocation.{Run}

  import Lightning.InvocationFixtures
  import Lightning.JobsFixtures
  import Lightning.ProjectsFixtures
  import Lightning.AccountsFixtures

  import Lightning.Helpers, only: [ms_to_human: 1]

  import Swoosh.TestAssertions

  describe "FailureAlert" do
    setup do
      user = user_fixture()
      project = project_fixture(project_users: [%{user_id: user.id}])

      # for test purpose we'll config to 3 emails within 1mn
      period =
        Application.get_env(:lightning, Lightning.FailureAlerter)
        |> Keyword.get(:time_scale)
        |> ms_to_human()

      %{job: job, trigger: trigger} =
        workflow_job_fixture(
          workflow_name: "workflow-a",
          project_id: project.id,
          body: ~s[fn(state => { throw new Error("I'm supposed to fail.") })]
        )

      work_order = work_order_fixture(workflow_id: job.workflow_id)
      dataclip = dataclip_fixture()

      reason =
        reason_fixture(
          trigger_id: trigger.id,
          dataclip_id: dataclip.id
        )

      {:ok, attempt_run} =
        AttemptRun.new()
        |> Ecto.Changeset.put_assoc(
          :attempt,
          Attempt.changeset(%Attempt{}, %{
            work_order_id: work_order.id,
            reason_id: reason.id
          })
        )
        |> Ecto.Changeset.put_assoc(
          :run,
          Run.changeset(%Run{}, %{
            project_id: project.id,
            job_id: job.id,
            input_dataclip_id: dataclip.id
          })
        )
        |> Repo.insert()

      %{job: job2, trigger: trigger2} =
        workflow_job_fixture(
          workflow_name: "workflow-b",
          project_id: project.id,
          body: ~s[fn(state => { throw new Error("I also fail.") })]
        )

      work_order2 = work_order_fixture(workflow_id: job2.workflow_id)
      dataclip = dataclip_fixture()

      reason =
        reason_fixture(
          trigger_id: trigger2.id,
          dataclip_id: dataclip.id
        )

      {:ok, attempt_run2} =
        AttemptRun.new()
        |> Ecto.Changeset.put_assoc(
          :attempt,
          Attempt.changeset(%Attempt{}, %{
            work_order_id: work_order2.id,
            reason_id: reason.id
          })
        )
        |> Ecto.Changeset.put_assoc(
          :run,
          Run.changeset(%Run{}, %{
            project_id: project.id,
            job_id: job2.id,
            input_dataclip_id: dataclip.id
          })
        )
        |> Repo.insert()

      %{
        period: period,
        user: user,
        project: project,
        attempt_run: attempt_run,
        work_order: work_order,
        attempt_run2: attempt_run2
      }
    end

    test "sends a limited number of failure alert emails to a subscribed user.",
         %{
           project: project,
           attempt_run: attempt_run,
           work_order: work_order,
           period: period
         } do
      # The first three failed runs for this workflow will trigger emails.
      Pipeline.process(attempt_run)
      Pipeline.process(attempt_run)
      Pipeline.process(attempt_run)

      # And the 4th, when the rate limit is reached, will NOT trigger a 4th email.
      Pipeline.process(attempt_run)

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
      assert html_body =~ work_order.id

      assert html_body =~
               "/projects/#{project.id}/runs/#{attempt_run.run_id}"

      s2 = "\"workflow-a\" has failed 2 times in the last #{period}."
      assert_receive {:email, %Swoosh.Email{subject: ^s2}}, 1500

      s3 = "\"workflow-a\" has failed 3 times in the last #{period}."
      assert_receive {:email, %Swoosh.Email{subject: ^s3}}, 1500

      s4 = "\"workflow-a\" has failed 4 times in the last #{period}."
      refute_receive {:email, %Swoosh.Email{subject: ^s4}}, 250
    end

    test "sends a failure alert email for a workflow even if another workflow has been rate limited.",
         %{attempt_run: attempt_run, attempt_run2: attempt_run2, period: period} do
      Pipeline.process(attempt_run)
      Pipeline.process(attempt_run)
      Pipeline.process(attempt_run)
      Pipeline.process(attempt_run2)

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

    test "does not send failure emails to users who have unsubscribed" do
      user = user_fixture()

      project =
        project_fixture(
          project_users: [%{user_id: user.id, failure_alert: false}]
        )

      %{job: job, trigger: trigger} =
        workflow_job_fixture(
          workflow_name: "workflow-a",
          project_id: project.id,
          body: ~s[fn(state => { throw new Error("I'm supposed to fail.") })]
        )

      work_order = work_order_fixture(workflow_id: job.workflow_id)
      dataclip = dataclip_fixture()

      reason =
        reason_fixture(
          trigger_id: trigger.id,
          dataclip_id: dataclip.id
        )

      {:ok, attempt_run} =
        AttemptRun.new()
        |> Ecto.Changeset.put_assoc(
          :attempt,
          Attempt.changeset(%Attempt{}, %{
            work_order_id: work_order.id,
            reason_id: reason.id
          })
        )
        |> Ecto.Changeset.put_assoc(
          :run,
          Run.changeset(%Run{}, %{
            project_id: project.id,
            job_id: job.id,
            input_dataclip_id: dataclip.id
          })
        )
        |> Repo.insert()

      Pipeline.process(attempt_run)

      refute_email_sent(subject: "\"workflow-a\" failed.")
    end

    test "does not increment the rate-limiter counter when an email is not delivered.",
         %{attempt_run: attempt_run, work_order: work_order} do
      [time_scale: time_scale, rate_limit: rate_limit] =
        Application.fetch_env!(:lightning, Lightning.FailureAlerter)

      Pipeline.process(attempt_run)

      {:ok, {0, ^rate_limit, _, _, _}} =
        Hammer.inspect_bucket(work_order.workflow_id, time_scale, rate_limit)

      assert_email_sent(subject: "\"workflow-a\" failed.")

      stub(Lightning.FailureEmail, :deliver_failure_email, fn _, _ ->
        {:error}
      end)

      Pipeline.process(attempt_run)

      refute_email_sent(subject: "\"workflow-a\" failed.")

      # nothing changed
      {:ok, {0, ^rate_limit, _, _, _}} =
        Hammer.inspect_bucket(work_order.workflow_id, time_scale, rate_limit)
    end
  end
end
