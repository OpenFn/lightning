defmodule Lightning.AttemptServiceTest do
  use Lightning.DataCase, async: true

  describe "attempts" do
    import Lightning.JobsFixtures
    import Lightning.InvocationFixtures
    alias Lightning.AttemptService

    alias Lightning.Invocation.{Event, Run}
    alias Lightning.Attempt

    test "create/3 returns an Event, a Run and an Attempt" do
      job = workflow_job_fixture()
      workorder = workorder_fixture(workflow_id: job.workflow_id)
      reason = reason_fixture(trigger_id: job.trigger.id)

      job_id = job.id
      reason_id = reason.id
      data_clip_id = reason.dataclip_id

      assert {:ok,
              %{
                attempt: %Attempt{
                  reason_id: ^reason_id,
                  runs: [%Run{job_id: ^job_id, input_dataclip_id: ^data_clip_id}]
                },
                event: %Event{},
                run: %Run{}
              }} =
               AttemptService.create_attempt(
                 workorder,
                 job,
                 reason
               )
    end
  end
end
