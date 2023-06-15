defmodule Lightning.DigestEmailWorkerTest do
  use Lightning.DataCase, async: true

  alias Lightning.{
    AccountsFixtures,
    InvocationFixtures,
    JobsFixtures,
    ProjectsFixtures,
    WorkflowsFixtures,
    DigestEmailWorker
  }

  import Lightning.Factories

  describe "perform/1" do
    test "projects that are scheduled for deletion are not part of the projects for which digest alerts are sent" do
      user = AccountsFixtures.user_fixture()

      project =
        ProjectsFixtures.project_fixture(
          scheduled_deletion: Timex.now(),
          project_users: [
            %{user_id: user.id, digest: :daily}
          ]
        )

      assert project.project_users |> length() == 1

      {:ok, notified_project_users} =
        DigestEmailWorker.perform(%Oban.Job{
          args: %{"type" => "daily_project_digest"}
        })

      assert notified_project_users |> length() == 0
    end

    test "all project users of different project that have a digest of :daily, :weekly, and :monthly" do
      user_1 = AccountsFixtures.user_fixture()
      user_2 = AccountsFixtures.user_fixture()
      user_3 = AccountsFixtures.user_fixture()

      ProjectsFixtures.project_fixture(
        project_users: [
          %{user_id: user_1.id, digest: :daily},
          %{user_id: user_2.id, digest: :weekly},
          %{user_id: user_3.id, digest: :monthly}
        ]
      )

      ProjectsFixtures.project_fixture(
        project_users: [
          %{user_id: user_1.id, digest: :monthly},
          %{user_id: user_2.id, digest: :daily},
          %{user_id: user_3.id, digest: :daily}
        ]
      )

      ProjectsFixtures.project_fixture(
        project_users: [
          %{user_id: user_1.id, digest: :weekly},
          %{user_id: user_2.id, digest: :daily},
          %{user_id: user_3.id, digest: :weekly}
        ]
      )

      {:ok, daily_project_users} =
        DigestEmailWorker.perform(%Oban.Job{
          args: %{"type" => "daily_project_digest"}
        })

      {:ok, weekly_project_users} =
        DigestEmailWorker.perform(%Oban.Job{
          args: %{"type" => "weekly_project_digest"}
        })

      {:ok, monthly_project_users} =
        DigestEmailWorker.perform(%Oban.Job{
          args: %{"type" => "monthly_project_digest"}
        })

      assert daily_project_users |> length() == 4
      assert weekly_project_users |> length() == 3
      assert monthly_project_users |> length() == 2
    end
  end

  describe "get_digest_data/3" do
    test "Gets project digest data" do
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

      job_a_trigger =
        insert(:trigger, %{workflow_id: workflow_a.id, workflow: workflow_a})

      _unused_edge =
        insert(:edge, %{
          workflow: workflow_a,
          workflow_id: workflow_a.id,
          target_job: job_a,
          source_trigger: job_a_trigger,
          condition: :always
        })

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

      reason = InvocationFixtures.reason_fixture(trigger_id: job_a_trigger.id)

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

      start_date = DigestEmailWorker.digest_to_date(:monthly)
      end_date = Timex.now()

      # TODO: When implementing issue #795, please uncomment the lines with rerun_workorders for testing.

      assert DigestEmailWorker.get_digest_data(workflow_a, start_date, end_date) ==
               %{
                 failed_workorders: 1,
                 #  rerun_workorders: 1,
                 successful_workorders: 2,
                 workflow: workflow_a
               }

      assert DigestEmailWorker.get_digest_data(workflow_b, start_date, end_date) ==
               %{
                 failed_workorders: 0,
                 #  rerun_workorders: 1,
                 successful_workorders: 2,
                 workflow: workflow_b
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
