defmodule Lightning.WorkOrdersTest do
  use Lightning.DataCase, async: true

  import Lightning.Factories

  alias Lightning.WorkOrders

  describe "create_for/2" do
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
  end

  describe "retry/1" do
    setup do
      [job_a, job_b, job_c] = jobs = build_list(3, :job)
      trigger = build(:trigger, type: :webhook)

      workflow =
        build(:workflow)
        |> with_job(job_a)
        |> with_job(job_b)
        |> with_job(job_c)
        |> with_trigger(trigger)
        |> with_edge({trigger, job_a})
        |> with_edge({job_a, job_b})
        |> with_edge({job_b, job_c})
        |> insert()

      %{
        workflow: workflow,
        trigger: trigger |> Repo.reload!(),
        jobs: jobs |> Repo.reload!()
      }
    end

    test "retrying an attempt from the start", %{
      workflow: workflow,
      trigger: trigger,
      jobs: [job | _rest]
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

      refute retry_attempt.id == attempt.id
      assert retry_attempt.dataclip_id == dataclip.id
      assert retry_attempt.starting_job.id == job.id
      assert retry_attempt.created_by.id == user.id
      assert retry_attempt.work_order_id == attempt.work_order_id
      assert retry_attempt.state == "available"

      assert retry_attempt |> Repo.preload(:runs) |> Map.get(:runs) == [],
             "retrying an attempt from the start should not copy over runs"
    end

    test "retrying an attempt from a run that isn't the first", %{
      workflow: workflow,
      trigger: trigger,
      jobs: [job_a, job_b, job_c]
    } do
      user = insert(:user)
      dataclip = insert(:dataclip)
      output_dataclip = insert(:dataclip)

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
                first_run =
                  insert(:run,
                    job: job_a,
                    input_dataclip: dataclip,
                    output_dataclip: output_dataclip
                  ),
                second_run =
                  insert(:run, job: job_b, input_dataclip: output_dataclip),
                insert(:run, job: job_c)
              ]
            }
          ]
        )

      {:ok, retry_attempt} =
        WorkOrders.retry(attempt, second_run, created_by: user)

      refute retry_attempt.id == attempt.id
      assert retry_attempt.dataclip_id == output_dataclip.id
      assert retry_attempt.starting_job.id == job_b.id
      assert retry_attempt.created_by.id == user.id
      assert retry_attempt.work_order_id == attempt.work_order_id
      assert retry_attempt.state == "available"

      runs = Ecto.assoc(retry_attempt, :runs) |> Repo.all()
      assert runs |> Enum.map(& &1.id) == [first_run.id]
    end
  end
end
