defmodule Lightning.FactoriesTest do
  use Lightning.DataCase, async: true

  alias Lightning.Factories

  import LightningWeb.ConnCase, only: [create_project_for_current_user: 1]

  test "build(:trigger) overrides default assoc" do
    job = %{workflow: workflow} = Factories.insert(:job)

    trigger =
      Factories.insert(:trigger, %{
        type: :cron,
        cron_expression: "* * * * *",
        workflow: job.workflow
      })

    assert trigger.workflow.id == workflow.id
  end

  test "insert/1 inserts a record" do
    trigger = Factories.insert(:trigger)
    assert trigger
  end

  describe "work_order" do
    setup :register_user
    setup :create_project_for_current_user
    setup :create_workflow_trigger_job

    test "with_attempt associates a new attempt to a workorder", %{
      workflow: workflow,
      trigger: trigger,
      job: job
    } do
      dataclip = Factories.insert(:dataclip)

      assert work_order =
               Factories.insert(:workorder, workflow: workflow)
               |> Factories.with_attempt(
                 dataclip: dataclip,
                 starting_trigger: trigger,
                 runs: [
                   %{
                     job: job,
                     started_at: Factories.build(:timestamp),
                     finished_at: nil,
                     exit_code: nil,
                     input_dataclip: dataclip
                   }
                 ]
               )

      attempt_id = hd(Repo.all(Lightning.Attempt)).id

      assert hd(work_order.attempts).id == attempt_id

      work_order = Repo.preload(work_order, :attempts)

      assert hd(work_order.attempts).id == attempt_id
    end
  end

  defp register_user(_context) do
    %{user: Lightning.AccountsFixtures.user_fixture()}
  end

  defp create_workflow_trigger_job(%{project: project}) do
    workflow = Factories.insert(:workflow, project: project)
    trigger = Factories.insert(:trigger, type: :webhook, workflow: workflow)
    job = Factories.insert(:job, workflow: workflow)

    {:ok, %{workflow: workflow, trigger: trigger, job: job}}
  end
end
