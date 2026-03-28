defmodule Lightning.Workflows.SchedulerTest do
  @moduledoc false
  use Lightning.DataCase, async: true

  alias Lightning.Invocation
  alias Lightning.Repo
  alias Lightning.Run
  alias Lightning.Workflows.Scheduler

  describe "enqueue_cronjobs/1" do
    test "cron_cursor_job_id nil, no prior run: creates empty global dataclip" do
      job = insert(:job)

      trigger =
        insert(:trigger, %{
          type: :cron,
          cron_expression: "* * * * *",
          workflow: job.workflow
        })

      insert(:edge, %{
        workflow: job.workflow,
        source_trigger: trigger,
        target_job: job
      })

      with_snapshot(job.workflow)

      Mox.expect(
        Lightning.Extensions.MockUsageLimiter,
        :limit_action,
        fn _action, _context -> :ok end
      )

      Scheduler.enqueue_cronjobs()

      run = Repo.one(Run)

      assert run.starting_trigger_id == trigger.id

      run =
        Repo.preload(run, dataclip: Invocation.Query.dataclip_with_body())

      assert run.dataclip.type == :global
      assert Jason.decode!(run.dataclip.body) == %{}
    end

    test "cron_cursor_job_id nil, prior successful run: uses final_dataclip_id" do
      job = insert(:job)

      trigger =
        insert(:trigger, %{
          type: :cron,
          cron_expression: "* * * * *",
          workflow: job.workflow
        })

      insert(:edge, %{
        workflow: job.workflow,
        source_trigger: trigger,
        target_job: job
      })

      final_dataclip =
        insert(:dataclip,
          type: :step_result,
          body: %{"final" => "state"}
        )

      with_snapshot(job.workflow)

      insert(:run,
        work_order:
          build(:workorder,
            workflow: job.workflow,
            dataclip: insert(:dataclip),
            trigger: trigger,
            state: :success
          ),
        starting_trigger: trigger,
        state: :success,
        dataclip: insert(:dataclip),
        final_dataclip: final_dataclip,
        finished_at: DateTime.utc_now(),
        steps: []
      )

      Mox.expect(
        Lightning.Extensions.MockUsageLimiter,
        :limit_action,
        fn _action, _context -> :ok end
      )

      Scheduler.enqueue_cronjobs()

      new_run =
        Run
        |> last(:inserted_at)
        |> preload(dataclip: ^Invocation.Query.dataclip_with_body())
        |> Repo.one()

      assert new_run.dataclip.type == :step_result
      assert Jason.decode!(new_run.dataclip.body) == %{"final" => "state"}
    end

    test "cron_cursor_job_id set, no prior run: creates empty global dataclip" do
      job = insert(:job)

      trigger =
        insert(:trigger, %{
          type: :cron,
          cron_expression: "* * * * *",
          workflow: job.workflow,
          cron_cursor_job_id: job.id
        })

      insert(:edge, %{
        workflow: job.workflow,
        source_trigger: trigger,
        target_job: job
      })

      with_snapshot(job.workflow)

      Mox.expect(
        Lightning.Extensions.MockUsageLimiter,
        :limit_action,
        fn _action, _context -> :ok end
      )

      Scheduler.enqueue_cronjobs()

      run = Repo.one(Run)

      assert run.starting_trigger_id == trigger.id

      run =
        Repo.preload(run, dataclip: Invocation.Query.dataclip_with_body())

      assert run.dataclip.type == :global
      assert Jason.decode!(run.dataclip.body) == %{}
    end

    test "cron_cursor_job_id set, prior successful run: uses that job's output" do
      job =
        insert(:job,
          body: "fn(state => { console.log(state); return { changed: true }; })"
        )

      trigger =
        insert(:trigger, %{
          type: :cron,
          cron_expression: "* * * * *",
          workflow: job.workflow,
          cron_cursor_job_id: job.id
        })

      insert(:edge, %{
        workflow: job.workflow,
        source_trigger: trigger,
        target_job: job
      })

      dataclip = insert(:dataclip)

      with_snapshot(job.workflow)

      run =
        insert(:run,
          work_order:
            build(:workorder,
              workflow: job.workflow,
              dataclip: dataclip,
              trigger: trigger,
              state: :success
            ),
          starting_trigger: trigger,
          state: :success,
          dataclip: dataclip,
          steps: [
            build(:step,
              exit_reason: "success",
              job: job,
              input_dataclip: dataclip,
              output_dataclip:
                build(:dataclip, type: :step_result, body: %{"changed" => true})
            )
          ]
        )

      [old_step] = run.steps

      Mox.expect(
        Lightning.Extensions.MockUsageLimiter,
        :limit_action,
        fn _action, _context -> :ok end
      )

      Scheduler.enqueue_cronjobs()

      new_run =
        Run
        |> last(:inserted_at)
        |> preload(dataclip: ^Invocation.Query.dataclip_with_body())
        |> Repo.one()

      assert run.dataclip.type == :http_request
      assert old_step.input_dataclip.type == :http_request
      assert old_step.input_dataclip.body == %{}

      refute new_run.id == run.id
      assert new_run.dataclip.type == :step_result

      assert Jason.decode!(new_run.dataclip.body) ==
               old_step.output_dataclip.body
    end
  end
end
