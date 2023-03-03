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

  import Swoosh.TestAssertions

  # for test purpose we'll config to 3 emails within 1mn

  describe "failure_alert" do
    setup do
      user = user_fixture()
      project = project_fixture(project_users: [%{user_id: user.id}])

      job =
        workflow_job_fixture(
          workflow_name: "specific-workflow",
          project_id: project.id,
          body: ~s[fn(state => { throw new Error("I'm supposed to fail.") })]
        )

      work_order = work_order_fixture(workflow_id: job.workflow_id)
      dataclip = dataclip_fixture()

      reason =
        reason_fixture(
          trigger_id: job.trigger.id,
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

      job2 =
        workflow_job_fixture(
          workflow_name: "another-workflow",
          project_id: project.id,
          body: ~s[fn(state => { throw new Error("I'm supposed to fail.") })]
        )

      work_order2 = work_order_fixture(workflow_id: job2.workflow_id)
      dataclip = dataclip_fixture()

      reason =
        reason_fixture(
          trigger_id: job2.trigger.id,
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
        user: user,
        project: project,
        attempt_run: attempt_run,
        work_order: work_order,
        attempt_run2: attempt_run2
      }
    end

    test "failing workflow sends failure email to user having failure_alert to true",
         %{project: project, attempt_run: attempt_run, work_order: work_order} do
      # 1/3 within 1mn
      Pipeline.process(attempt_run)
      # 2/3 within 1mn
      Pipeline.process(attempt_run)
      # 3/3 within 1mn
      Pipeline.process(attempt_run)
      # rate limit reached -> won't send email
      Pipeline.process(attempt_run)

      Oban.drain_queue(Oban, queue: :workflow_failures)

      assert_receive {:email,
                      %Swoosh.Email{
                        subject: "1th failure for workflow specific-workflow",
                        html_body: html_body
                      }}

      assert html_body =~ "specific-workflow"
      assert html_body =~ work_order.id

      assert html_body =~
               "/projects/#{project.id}/runs/#{attempt_run.run_id}"

      assert_receive {:email,
                      %Swoosh.Email{
                        subject: "2th failure for workflow specific-workflow"
                      }}

      assert_receive {:email,
                      %Swoosh.Email{
                        subject: "3th failure for workflow specific-workflow"
                      }}

      refute_receive {:email,
                      %Swoosh.Email{
                        subject: "4th failure for workflow specific-workflow"
                      }}
    end

    test "failing workflow sends email even if another workflow hits rate limit within the same time scale",
         %{attempt_run: attempt_run, attempt_run2: attempt_run2} do
      Pipeline.process(attempt_run)
      Pipeline.process(attempt_run)
      Pipeline.process(attempt_run)
      Pipeline.process(attempt_run2)

      Oban.drain_queue(Oban, queue: :workflow_failures)

      assert_receive {:email,
                      %Swoosh.Email{
                        subject: "1th failure for workflow specific-workflow"
                      }}

      assert_receive {:email,
                      %Swoosh.Email{
                        subject: "2th failure for workflow specific-workflow"
                      }}

      assert_receive {:email,
                      %Swoosh.Email{
                        subject: "3th failure for workflow specific-workflow"
                      }}

      assert_receive {:email,
                      %Swoosh.Email{
                        subject: "1th failure for workflow another-workflow"
                      }}
    end

    test "failing workflow does not send failure email to user having failure_alert to false" do
      user = user_fixture()

      project =
        project_fixture(
          project_users: [%{user_id: user.id, failure_alert: false}]
        )

      job =
        workflow_job_fixture(
          workflow_name: "specific-workflow",
          project_id: project.id,
          body: ~s[fn(state => { throw new Error("I'm supposed to fail.") })]
        )

      work_order = work_order_fixture(workflow_id: job.workflow_id)
      dataclip = dataclip_fixture()

      reason =
        reason_fixture(
          trigger_id: job.trigger.id,
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

      refute_email_sent(subject: "1th failure for workflow specific-workflow")
    end

    test "not delivered email does not change the remaining count",
         %{attempt_run: attempt_run, work_order: work_order} do
      [time_scale: time_scale, rate_limit: rate_limit] =
        Application.fetch_env!(:lightning, Lightning.FailureAlerter)

      Pipeline.process(attempt_run)

      {:ok, {0, ^rate_limit, _, _, _}} =
        Hammer.inspect_bucket(work_order.workflow_id, time_scale, rate_limit)

      assert_email_sent(subject: "1th failure for workflow specific-workflow")

      stub(Lightning.FailureEmail, :deliver_failure_email, fn _, _ ->
        {:error}
      end)

      Pipeline.process(attempt_run)

      refute_email_sent(subject: "1th failure for workflow specific-workflow")

      # nothing changed
      {:ok, {0, ^rate_limit, _, _, _}} =
        Hammer.inspect_bucket(work_order.workflow_id, time_scale, rate_limit)
    end
  end
end
