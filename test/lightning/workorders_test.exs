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
      user = AccountsFixtures.user_fixture()

      project =
        ProjectsFixtures.project_fixture(
          project_users: [%{user_id: user.id, digest: :daily}]
        )

      workflow = WorkflowsFixtures.workflow_fixture(project_id: project.id)

      job =
        JobsFixtures.job_fixture(
          project_id: project.id,
          workflow_id: workflow.id
        )

      workorder_1 =
        InvocationFixtures.work_order_fixture(workflow_id: workflow.id)

      workorder_2 =
        InvocationFixtures.work_order_fixture(workflow_id: workflow.id)

      reason = InvocationFixtures.reason_fixture()

      create_run(workorder_1, reason, %{
        project_id: project.id,
        job_id: job.id,
        input_dataclip_id: reason.dataclip_id,
        exit_code: 0,
        finished_at: Timex.now()
      })

      create_run(workorder_2, reason, %{
        project_id: project.id,
        job_id: job.id,
        input_dataclip_id: reason.dataclip_id,
        exit_code: 0,
        finished_at: Timex.now()
      })

      assert Workorders.get_digest_data(workflow, :daily) == %{
               failed_workorders: 0,
               rerun_workorders: 0,
               successful_workorders: 2,
               workflow_name: workflow.name
             }

      workorder_1 =
        InvocationFixtures.work_order_fixture(workflow_id: workflow.id)

      workorder_2 =
        InvocationFixtures.work_order_fixture(workflow_id: workflow.id)

      workorder_3 =
        InvocationFixtures.work_order_fixture(workflow_id: workflow.id)

      create_run(workorder_1, reason, %{
        project_id: project.id,
        job_id: job.id,
        input_dataclip_id: reason.dataclip_id,
        exit_code: 0,
        finished_at: Timex.now()
      })

      create_run(workorder_2, reason, %{
        project_id: project.id,
        job_id: job.id,
        input_dataclip_id: reason.dataclip_id,
        exit_code: 1,
        finished_at: Timex.now()
      })

      create_run(workorder_3, reason, %{
        project_id: project.id,
        job_id: job.id,
        input_dataclip_id: reason.dataclip_id,
        exit_code: 1,
        finished_at: Timex.now()
      })

      create_run(workorder_3, reason, %{
        project_id: project.id,
        job_id: job.id,
        input_dataclip_id: reason.dataclip_id,
        exit_code: 1,
        finished_at: Timex.now() |> Timex.shift(days: -7)
      })

      create_run(workorder_3, reason, %{
        project_id: project.id,
        job_id: job.id,
        input_dataclip_id: reason.dataclip_id,
        exit_code: 0,
        finished_at:
          Timex.now()
          |> Timex.shift(months: -1)
          |> Timex.beginning_of_month()
          |> Timex.shift(hours: 4)
      })

      assert Workorders.get_digest_data(workflow, :daily) == %{
               failed_workorders: 2,
               rerun_workorders: 0,
               successful_workorders: 3,
               workflow_name: workflow.name
             }

      assert Workorders.get_digest_data(workflow, :weekly) == %{
               failed_workorders: 3,
               rerun_workorders: 0,
               successful_workorders: 3,
               workflow_name: workflow.name
             }

      assert Workorders.get_digest_data(workflow, :monthly) == %{
               failed_workorders: 3,
               rerun_workorders: 0,
               successful_workorders: 4,
               workflow_name: workflow.name
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
