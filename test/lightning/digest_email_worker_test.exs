defmodule Lightning.DigestEmailWorkerTest do
  use Lightning.DataCase, async: true

  alias Lightning.DigestEmailWorker

  import Lightning.Factories

  describe "perform/1" do
    test "projects that are scheduled for deletion are not part of the projects for which digest alerts are sent" do
      user = insert(:user)

      project =
        insert(:project,
          scheduled_deletion: Timex.now(),
          project_users: [
            %{user_id: user.id, digest: :daily}
          ]
        )

      assert length(project.project_users) == 1

      {:ok, result} =
        DigestEmailWorker.perform(%Oban.Job{
          args: %{"type" => "daily_project_digest"}
        })

      assert length(result.notified_users) == 0
      assert length(result.skipped_users) == 0
    end

    test "all project users of different project that have a digest of :daily, :weekly, and :monthly" do
      [user_1, user_2, user_3] = insert_list(3, :user)

      project_1 =
        insert(:project,
          project_users: [
            %{user_id: user_1.id, digest: :daily},
            %{user_id: user_2.id, digest: :weekly},
            %{user_id: user_3.id, digest: :monthly}
          ]
        )

      project_2 =
        insert(:project,
          project_users: [
            %{user_id: user_1.id, digest: :monthly},
            %{user_id: user_2.id, digest: :daily},
            %{user_id: user_3.id, digest: :daily}
          ]
        )

      project_3 =
        insert(:project,
          project_users: [
            %{user_id: user_1.id, digest: :weekly},
            %{user_id: user_2.id, digest: :daily},
            %{user_id: user_3.id, digest: :weekly}
          ]
        )

      insert(:simple_workflow, project: project_1)
      insert(:simple_workflow, project: project_2)
      insert(:simple_workflow, project: project_3)

      {:ok, daily_result} =
        DigestEmailWorker.perform(%Oban.Job{
          args: %{"type" => "daily_project_digest"}
        })

      {:ok, weekly_result} =
        DigestEmailWorker.perform(%Oban.Job{
          args: %{"type" => "weekly_project_digest"}
        })

      {:ok, monthly_result} =
        DigestEmailWorker.perform(%Oban.Job{
          args: %{"type" => "monthly_project_digest"}
        })

      assert length(daily_result.notified_users) == 4
      assert length(weekly_result.notified_users) == 3
      assert length(monthly_result.notified_users) == 2

      assert length(daily_result.skipped_users) == 0
      assert length(weekly_result.skipped_users) == 0
      assert length(monthly_result.skipped_users) == 0
    end

    test "skips users when project has no workflows" do
      user = insert(:user)

      _project =
        insert(:project,
          project_users: [
            %{user_id: user.id, digest: :daily}
          ]
        )

      {:ok, result} =
        DigestEmailWorker.perform(%Oban.Job{
          args: %{"type" => "daily_project_digest"}
        })

      assert result.notified_users == []
      assert length(result.skipped_users) == 1
    end
  end

  describe "get_digest_data/3" do
    test "Gets project digest data" do
      user = insert(:user)

      project =
        insert(:project, project_users: [%{user_id: user.id, digest: :daily}])

      workflow_a = insert(:simple_workflow, project: project)
      workflow_b = insert(:simple_workflow, project: project)

      create_runs(workflow_a, [:pending])
      create_runs(workflow_a, [:running, :success])
      create_runs(workflow_b, [:failed, :killed])
      create_runs(workflow_b, [:crashed, :success])
      create_runs(workflow_a, [:success])

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
                 failed_workorders: 3,
                 #  rerun_workorders: 1,
                 successful_workorders: 1,
                 workflow: workflow_b
               }
    end

    test "Gets project digest data with no activity for all digest periods" do
      user = insert(:user)

      project =
        insert(:project, project_users: [%{user_id: user.id, digest: :daily}])

      workflow = insert(:simple_workflow, project: project)

      for period <- [:daily, :weekly, :monthly] do
        start_date = DigestEmailWorker.digest_to_date(period)
        end_date = Timex.now()

        assert DigestEmailWorker.get_digest_data(workflow, start_date, end_date) ==
                 %{
                   failed_workorders: 0,
                   successful_workorders: 0,
                   workflow: workflow
                 }
      end
    end
  end

  defp create_runs(
         %{triggers: [trigger], jobs: [job], project: project} = workflow,
         status_list
       ) do
    dataclip = insert(:dataclip, project: project)

    Enum.each(status_list, fn status ->
      state =
        case status do
          :pending -> :available
          :running -> :claimed
          other -> other
        end

      insert(:workorder,
        workflow: workflow,
        trigger: trigger,
        dataclip: dataclip,
        state: status
      )
      |> with_run(
        state: state,
        dataclip: dataclip,
        starting_trigger: trigger,
        finished_at: build(:timestamp),
        steps: [
          build(:step,
            job: job,
            input_dataclip: dataclip,
            started_at: build(:timestamp),
            finished_at: build(:timestamp)
          )
        ]
      )
    end)
  end
end
