defmodule Lightning.WorkOrdersTest do
  use Lightning.DataCase, async: true

  import Lightning.Factories

  alias Lightning.WorkOrders

  setup do
    job = build(:job)
    trigger = build(:trigger)

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

  test "creating a webhook triggered workorder", %{
    workflow: workflow,
    trigger: trigger
  } do
    dataclip = insert(:dataclip)

    {:ok, workorder} =
      WorkOrders.create(workflow, trigger: trigger, dataclip: dataclip)

    assert workorder.workflow_id == workflow.id
    assert workorder.trigger_id == trigger.id
    assert workorder.dataclip_id == dataclip.id

    [attempt] = workorder.attempts

    # assert attempt.trigger.id == trigger.id

    attempt |> Repo.reload!() |> Repo.preload(:trigger) |> IO.inspect()
  end
end
