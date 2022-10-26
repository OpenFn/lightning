defmodule Lightning.WorkOrderServiceTest do
  use Lightning.DataCase, async: true

  alias Lightning.WorkOrderService

  import Lightning.{AccountsFixtures, JobsFixtures, InvocationFixtures}

  describe "multi_for_manual/3" do
    test "creates a manual workorder" do
      job = job_fixture()
      dataclip = dataclip_fixture()
      user = user_fixture()

      {:ok, %{attempt_run: attempt_run}} =
        WorkOrderService.multi_for_manual(job, dataclip, user)
        |> Repo.transaction()

      assert attempt_run.run.job_id == job.id
      assert attempt_run.run.input_dataclip_id == dataclip.id
      assert attempt_run.attempt.reason.dataclip_id == dataclip.id
      assert attempt_run.attempt.reason.user_id == user.id
      assert attempt_run.attempt.reason.type == :manual
    end
  end
end
