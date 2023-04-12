defmodule Lightning.WorkordersTest do
  use Lightning.DataCase, async: true

  alias Lightning.{
    AccountsFixtures,
    InvocationFixtures,
    JobsFixtures,
    ProjectsFixtures,
    WorkflowsFixtures,
    Workorders
  }

  describe "Project digest" do
    test "Gets project digest data" do
      # """
      # Given:

      # Project: test

      # Workorder A - workflow A
      # - Attempt 1 finished 12/04/2023

      # Workorder B - workflow A
      # - Attempt 2 finished 12/04/2023: success
      # - Attempt 1 finished 11/04/2023: failure

      # Workorder C - workflow B
      # - Attempt 2 finished 12/04/2023: success
      # - Attempt 1 finished 10/04/2023: failure

      # Workorder D - workflow B
      # - Attempt 2 finished 12/04/2023: success
      # - Attempt 1 finished 10/04/2023: success

      # Workorder E - workflow A
      # - Attempt 1 finished 12/04/2023: failure
      # """

      user = AccountsFixtures.user_fixture()

      project =
        ProjectsFixtures.project_fixture(
          project_users: [%{user_id: user.id, digest: :daily}]
        )

      workflow_a = WorkflowsFixtures.workflow_fixture(project_id: project.id)
      workflow_b = WorkflowsFixtures.workflow_fixture(project_id: project.id)

      job_a =
        JobsFixtures.job_fixture(
          project_id: project.id,
          workflow_id: workflow_a.id
        )

      job_b =
        JobsFixtures.job_fixture(
          project_id: project.id,
          workflow_id: workflow_b.id
        )

      workorder_a =
        InvocationFixtures.work_order_fixture(workflow_id: workflow_a.id)

      workorder_b =
        InvocationFixtures.work_order_fixture(workflow_id: workflow_a.id)

      workorder_c =
        InvocationFixtures.work_order_fixture(workflow_id: workflow_b.id)

      workorder_d =
        InvocationFixtures.work_order_fixture(workflow_id: workflow_b.id)

      workorder_e =
        InvocationFixtures.work_order_fixture(workflow_id: workflow_a.id)

      reason = InvocationFixtures.reason_fixture(trigger_id: job_a.trigger.id)

      finished_at = Timex.now() |> Timex.shift(days: -1)

      create_run(workorder_a, reason, %{
        project_id: project.id,
        job_id: job_a.id,
        input_dataclip_id: reason.dataclip_id,
        exit_code: 0,
        finished_at: finished_at
      })

      create_run(workorder_b, reason, %{
        project_id: project.id,
        job_id: job_a.id,
        input_dataclip_id: reason.dataclip_id,
        exit_code: 1,
        finished_at: finished_at
      })

      create_run(workorder_b, reason, %{
        project_id: project.id,
        job_id: job_a.id,
        input_dataclip_id: reason.dataclip_id,
        exit_code: 0,
        finished_at: finished_at
      })

      create_run(workorder_c, reason, %{
        project_id: project.id,
        job_id: job_b.id,
        input_dataclip_id: reason.dataclip_id,
        exit_code: 1,
        finished_at: finished_at
      })

      create_run(workorder_c, reason, %{
        project_id: project.id,
        job_id: job_b.id,
        input_dataclip_id: reason.dataclip_id,
        exit_code: 0,
        finished_at: finished_at
      })

      create_run(workorder_d, reason, %{
        project_id: project.id,
        job_id: job_b.id,
        input_dataclip_id: reason.dataclip_id,
        exit_code: 0,
        finished_at: finished_at
      })

      create_run(workorder_d, reason, %{
        project_id: project.id,
        job_id: job_b.id,
        input_dataclip_id: reason.dataclip_id,
        exit_code: 0,
        finished_at: finished_at
      })

      create_run(workorder_e, reason, %{
        project_id: project.id,
        job_id: job_a.id,
        input_dataclip_id: reason.dataclip_id,
        exit_code: 1,
        finished_at: finished_at
      })

      assert Workorders.get_digest_data(workflow_a, :monthly) == %{
               failed_workorders: 1,
               rerun_workorders: 1,
               successful_workorders: 2,
               workflow_name: workflow_a.name
             }

      assert Workorders.get_digest_data(workflow_b, :monthly) == %{
               failed_workorders: 0,
               rerun_workorders: 1,
               successful_workorders: 2,
               workflow_name: workflow_b.name
             }
    end
  end

  defp create_run(workorder, reason, run_params) do
    Lightning.AttemptService.build_attempt(workorder, reason)
    |> Ecto.Changeset.put_assoc(:runs, [
      Lightning.Invocation.Run.changeset(%Lightning.Invocation.Run{}, run_params)
    ])
    |> Repo.insert()
  end
end
