defmodule Lightning.PipelineTest do
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


  describe "failure_alert" do
    test "failing workflow sends failure email to user having failure_alert to true" do

      user = user_fixture()
      project = project_fixture(project_users: [%{user_id: user.id}])

      job =
        workflow_job_fixture(
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
        assert_email_sent(subject: "1th failure for workflow workflow" )
    end

  end
end
