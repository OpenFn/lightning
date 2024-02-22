defmodule Lightning.Workflows.SchedulerTest do
  @moduledoc false
  use Lightning.DataCase, async: true

  import Mock

  alias Lightning.Invocation
  alias Lightning.Run
  alias Lightning.Workflows.Scheduler
  alias Lightning.Extensions.UsageLimiting.Action
  alias Lightning.Extensions.UsageLimiting.Context
  alias Lightning.Extensions.UsageLimiter

  describe "enqueue_cronjobs/1" do
    test "enqueues a cron job that's never been run before" do
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

      with_mock UsageLimiter, limit_action: fn _action, _context -> :ok end do
        Scheduler.enqueue_cronjobs()

        assert_called(
          UsageLimiter.limit_action(%Action{type: :new_run}, %Context{
            project_id: job.workflow.project_id
          })
        )
      end

      run = Repo.one(Run)

      assert run.starting_trigger_id == trigger.id

      run =
        Repo.preload(run, dataclip: Invocation.Query.dataclip_with_body())

      assert run.dataclip.type == :global
      assert run.dataclip.body == %{}
    end

    test "enqueues a cron job that has been run before" do
      job =
        insert(:job,
          body: "fn(state => { console.log(state); return { changed: true }; })"
        )

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

      dataclip = insert(:dataclip)

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

      with_mock UsageLimiter, limit_action: fn _action, _context -> :ok end do
        Scheduler.enqueue_cronjobs()

        assert_called(
          UsageLimiter.limit_action(%Action{type: :new_run}, %Context{
            project_id: job.workflow.project_id
          })
        )
      end

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
      assert new_run.dataclip.body == old_step.output_dataclip.body
    end
  end
end
