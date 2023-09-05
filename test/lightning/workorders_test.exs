defmodule Lightning.WorkOrdersTest do
  use Lightning.DataCase, async: true

  import Lightning.Factories

  alias Lightning.WorkOrders

  setup context do
    trigger_type = context |> Map.get(:trigger_type, :webhook)

    job = build(:job)
    trigger = build(:trigger, type: trigger_type)

    workflow =
      build(:workflow)
      |> with_job(job)
      |> with_trigger(trigger)
      |> with_edge({trigger, job})
      |> insert()

    %{
      workflow: workflow,
      trigger: trigger |> Repo.reload!(),
      job: job |> Repo.reload!()
    }
  end

  @tag trigger_type: :webhook
  test "creating a webhook triggered workorder", %{
    workflow: workflow,
    trigger: trigger
  } do
    dataclip = insert(:dataclip)

    {:ok, workorder} =
      WorkOrders.create_for(trigger, dataclip: dataclip, workflow: workflow)

    assert workorder.workflow_id == workflow.id
    assert workorder.trigger_id == trigger.id
    assert workorder.dataclip_id == dataclip.id

    [attempt] = workorder.attempts

    assert attempt.starting_trigger.id == trigger.id
  end

  @tag trigger_type: :cron
  test "creating a cron triggered workorder", %{
    workflow: workflow,
    trigger: trigger
  } do
    dataclip = insert(:dataclip)

    {:ok, workorder} =
      WorkOrders.create_for(trigger, dataclip: dataclip, workflow: workflow)

    assert workorder.workflow_id == workflow.id
    assert workorder.trigger_id == trigger.id
    assert workorder.dataclip_id == dataclip.id

    [attempt] = workorder.attempts

    assert attempt.starting_trigger.id == trigger.id
  end

  test "creating a manual workorder", %{workflow: workflow, job: job} do
    dataclip = insert(:dataclip)
    user = insert(:user)

    {:ok, workorder} =
      WorkOrders.create_for(job,
        dataclip: dataclip,
        workflow: workflow,
        created_by: user
      )

    assert workorder
  end
end
