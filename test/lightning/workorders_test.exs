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
    flunk("TODO")
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

  describe "retry/1" do
    test "retrying an attempt from the start", %{
      workflow: workflow,
      trigger: trigger,
      job: job
    } do
      user = insert(:user)
      dataclip = insert(:dataclip)
      # create existing complete attempt
      %{attempts: [attempt]} =
        insert(:workorder,
          workflow: workflow,
          trigger: trigger,
          dataclip: dataclip,
          attempts: [
            %{
              state: "resolved",
              dataclip: dataclip,
              starting_trigger: trigger,
              runs: [
                run = insert(:run, job: job, input_dataclip: dataclip)
              ]
            }
          ]
        )

      {:ok, retry_attempt} = WorkOrders.retry(attempt, run, created_by: user)

      # expect the attempt to be a new one, but with the same workorder
      # how do we distinguish between a new attempt and a retry?
      # starting_trigger and created_by works for webhooks/cron
      # but not for manual attempts
      # do we care about being able to tell _where_ a retry came from?

      refute retry_attempt.id == attempt.id
      assert retry_attempt.dataclip_id == dataclip.id
      assert retry_attempt.starting_job.id == job.id
      assert retry_attempt.work_order_id == attempt.work_order_id
      assert retry_attempt.state == "available"

      assert retry_attempt |> Repo.preload(:runs) |> Map.get(:runs) == [],
             "retrying an attempt from the start should not copy over runs"

      # IO.inspect(work_order, label: "work_order")

      # test retrying from the beginning
      # test retrying from a specific run

      # test retrying a manual attempt
      # do manual attempts continue executing?
    end
  end

  test "retrying an attempt from a run that isn't the first"
end
