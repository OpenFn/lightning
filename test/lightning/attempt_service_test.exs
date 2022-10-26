defmodule Lightning.AttemptServiceTest do
  use Lightning.DataCase, async: true

  import Lightning.JobsFixtures
  import Lightning.InvocationFixtures
  alias Lightning.Attempt
  alias Lightning.AttemptService
  alias Lightning.Invocation.{Run}

  describe "attempts" do
    test "create_attempt/3 returns a new Attempt, with a new Run" do
      job = workflow_job_fixture()
      work_order = work_order_fixture(workflow_id: job.workflow_id)
      reason = reason_fixture(trigger_id: job.trigger.id)

      job_id = job.id
      work_order_id = work_order.id
      reason_id = reason.id
      data_clip_id = reason.dataclip_id

      assert {:ok,
              %Attempt{
                work_order_id: ^work_order_id,
                reason_id: ^reason_id,
                runs: [%Run{job_id: ^job_id, input_dataclip_id: ^data_clip_id}]
              }} =
               AttemptService.create_attempt(
                 work_order,
                 job,
                 reason
               )
    end
  end

  describe "append/2" do
    test "adds a run to an existing attempt" do
      job = workflow_job_fixture()
      work_order = work_order_fixture(workflow_id: job.workflow_id)
      dataclip = dataclip_fixture()

      reason =
        reason_fixture(
          trigger_id: job.trigger.id,
          dataclip_id: dataclip.id
        )

      attempt =
        %Attempt{
          work_order_id: work_order.id,
          reason_id: reason.id
        }
        |> Repo.insert!()

      new_run =
        Run.changeset(%Run{}, %{
          project_id: job.workflow.project_id,
          job_id: job.id,
          input_dataclip_id: dataclip.id
        })

      {:ok, attempt_run} = AttemptService.append(attempt, new_run)

      assert Ecto.assoc(attempt_run.run, :attempts) |> Repo.all() == [attempt]
    end
  end
end
