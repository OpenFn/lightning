defmodule Lightning.DigestEmailWorkerTest do
  use Lightning.DataCase, async: true

  alias Lightning.{
    AccountsFixtures,
    ProjectsFixtures,
    DigestEmailWorker
  }

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
      |> with_attempt(
        state: state,
        dataclip: dataclip,
        starting_trigger: trigger,
        finished_at: build(:timestamp),
        runs: [
          build(:run,
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
