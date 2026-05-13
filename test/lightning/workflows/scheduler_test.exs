defmodule Lightning.Workflows.SchedulerTest do
  @moduledoc false
  use Lightning.DataCase, async: true

  import ExUnit.CaptureLog

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

  describe "enqueue_cronjobs/1 error isolation" do
    setup do
      Mox.verify_on_exit!()
      :ok
    end

    test "a raised exception in one edge does not prevent subsequent edges from being processed" do
      # Failing edge — its UsageLimiter check will raise.
      failing_job = insert(:job)

      failing_trigger =
        insert(:trigger, %{
          type: :cron,
          cron_expression: "* * * * *",
          workflow: failing_job.workflow
        })

      failing_edge =
        insert(:edge, %{
          workflow: failing_job.workflow,
          source_trigger: failing_trigger,
          target_job: failing_job
        })

      with_snapshot(failing_job.workflow)

      failing_project_id = failing_job.workflow.project_id
      failing_workflow_id = failing_job.workflow.id

      # Surviving edge — should still create a Run despite the other edge
      # raising.
      surviving_job = insert(:job)

      surviving_trigger =
        insert(:trigger, %{
          type: :cron,
          cron_expression: "* * * * *",
          workflow: surviving_job.workflow
        })

      insert(:edge, %{
        workflow: surviving_job.workflow,
        source_trigger: surviving_trigger,
        target_job: surviving_job
      })

      with_snapshot(surviving_job.workflow)

      # Raise only when invoked for the failing project; pass for the other.
      Mox.stub(
        Lightning.Extensions.MockUsageLimiter,
        :limit_action,
        fn _action, %{project_id: project_id} ->
          if project_id == failing_project_id do
            raise RuntimeError, "boom"
          else
            :ok
          end
        end
      )

      # Route Lightning.Sentry through the Mox-backed mock for this test.
      Mox.stub(Lightning.MockConfig, :sentry, fn -> Lightning.MockSentry end)

      # The scheduler must report the failing edge to Sentry exactly once,
      # with rich context for triage.
      Mox.expect(Lightning.MockSentry, :capture_exception, fn error, opts ->
        assert %RuntimeError{message: "boom"} = error
        assert opts[:tags][:type] == "scheduler"
        assert opts[:extra][:edge_id] == failing_edge.id
        assert opts[:extra][:trigger_id] == failing_trigger.id
        assert opts[:extra][:job_id] == failing_job.id
        assert opts[:extra][:workflow_id] == failing_workflow_id
        assert is_list(opts[:stacktrace])
        assert opts[:stacktrace] != []
        :ok
      end)

      logs = capture_log(fn -> Scheduler.enqueue_cronjobs() end)

      # The surviving edge created a Run; the failing edge did not.
      runs = Repo.all(Run)
      assert length(runs) == 1
      [run] = runs
      assert run.starting_trigger_id == surviving_trigger.id

      # The failure was logged with the formatted exception.
      assert logs =~ "Scheduler failed to invoke cronjob"
      assert logs =~ "boom"
    end
  end
end
