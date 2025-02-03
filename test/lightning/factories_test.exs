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

    test "with_run associates a new run to a workorder", %{
      workflow: workflow,
      trigger: trigger,
      job: job
    } do
      dataclip = Factories.insert(:dataclip)

      assert work_order =
               Factories.insert(:workorder, workflow: workflow)
               |> Factories.with_run(
                 dataclip: dataclip,
                 starting_trigger: trigger,
                 steps: [
                   %{
                     job: job,
                     started_at: Factories.build(:timestamp),
                     finished_at: nil,
                     input_dataclip: dataclip
                   }
                 ]
               )

      run_id = hd(Repo.all(Lightning.Run)).id

      assert hd(work_order.runs).id == run_id

      work_order = Repo.preload(work_order, :runs)

      assert hd(work_order.runs).id == run_id
    end
  end

  describe "collection_item" do
    test "has a sequence on both id and inserted_at" do
      items = build_list(100, :collection_item)

      assert items == Enum.sort_by(items, & &1.id)
      assert items == Enum.sort_by(items, & &1.inserted_at)
    end

    test "uses given inserted_at when saving the record" do
      now =
        DateTime.utc_now() |> DateTime.add(Enum.random(10..100), :second)

      assert %{inserted_at: ^now} = insert(:collection_item, inserted_at: now)
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
