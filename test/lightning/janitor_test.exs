defmodule Lightning.JanitorTest do
  require Lightning.Run
  use Lightning.DataCase, async: true
  alias Lightning.Janitor
  alias Lightning.Invocation
  import Lightning.Factories
  alias Lightning.Repo
  alias Lightning.Run

  describe "find_and_update_lost/0" do
    @tag :capture_log
    test "updates lost runs and their steps" do
      project =
        insert(:project,
          project_users: [%{user: build(:user), failure_alert: true}]
        )

      %{triggers: [trigger]} =
        workflow = insert(:simple_workflow, project: project, name: "pain perdu")

      dataclip = insert(:dataclip)

      an_hour_in_seconds = 3600

      work_order =
        insert(:workorder,
          workflow: workflow,
          trigger: trigger,
          dataclip: dataclip
        )

      lost_run =
        insert(:run,
          work_order: work_order,
          starting_trigger: trigger,
          dataclip: dataclip,
          state: :started,
          claimed_at: DateTime.utc_now() |> DateTime.add(-an_hour_in_seconds)
        )

      unfinished_step =
        insert(:step,
          runs: [lost_run],
          finished_at: nil,
          exit_reason: nil
        )

      normal_run =
        insert(:run,
          work_order: work_order,
          starting_trigger: trigger,
          dataclip: dataclip,
          state: :started,
          claimed_at: DateTime.utc_now()
        )

      allowable_long_run =
        insert(:run,
          work_order: work_order,
          starting_trigger: trigger,
          dataclip: dataclip,
          state: :started,
          options: %Lightning.Runs.RunOptions{
            # give a special timeout of an hour _plus_ 5 more seconds
            run_timeout_ms: an_hour_in_seconds * 1000 + 5000
          },
          claimed_at: DateTime.utc_now() |> DateTime.add(-an_hour_in_seconds)
        )

      lost_long_run =
        insert(:run,
          work_order: work_order,
          starting_trigger: trigger,
          dataclip: dataclip,
          state: :started,
          options: %Lightning.Runs.RunOptions{
            # give a special timeout of an hour _minus_ 20 seconds
            run_timeout_ms: an_hour_in_seconds * 1000 - 20_000
          },
          claimed_at: DateTime.utc_now() |> DateTime.add(-an_hour_in_seconds)
        )

      Janitor.find_and_update_lost()

      # should be marked lost
      reloaded_run = Repo.get(Run, lost_run.id)
      reloaded_step = Repo.get(Invocation.Step, unfinished_step.id)

      assert reloaded_run.state == :lost
      assert reloaded_step.exit_reason == "lost"

      # should NOT be marked lost, normal runtime
      reloaded_normal_run = Repo.get(Run, normal_run.id)
      assert reloaded_normal_run.state !== :lost

      # should NOT be marked lost, long runtime
      reloaded_allowable_long_run = Repo.get(Run, allowable_long_run.id)
      assert reloaded_allowable_long_run.state !== :lost

      # should be marked lost, despite having a long runtime
      reloaded_lost_long_run = Repo.get(Run, lost_long_run.id)
      assert reloaded_lost_long_run.state == :lost

      subject = "\"pain perdu\" (#{project.name}) failed"

      assert_receive {:email, %Swoosh.Email{subject: ^subject}},
                     1000
    end

    test "updates steps whose run has finished but step hasn't" do
      %{triggers: [trigger], jobs: [job_1 | _]} =
        workflow = insert(:simple_workflow)

      dataclip = insert(:dataclip)

      work_order =
        insert(:workorder,
          workflow: workflow,
          trigger: trigger,
          dataclip: dataclip
        )

      grace_period = Application.get_env(:lightning, :run_grace_period_seconds)

      finished_runs_with_unfinished_steps =
        Run.final_states()
        |> Enum.map(fn state ->
          insert(:run,
            work_order: work_order,
            starting_trigger: trigger,
            dataclip: dataclip,
            state: state,
            finished_at: DateTime.utc_now() |> DateTime.add(-grace_period),
            steps: [
              build(:step,
                job: job_1,
                finished_at: nil,
                exit_reason: nil
              )
            ]
          )
        end)

      finished_runs_with_finished_steps =
        Run.final_states()
        |> Enum.map(fn state ->
          insert(:run,
            work_order: work_order,
            starting_trigger: trigger,
            dataclip: dataclip,
            state: state,
            steps: [
              build(:step,
                job: job_1,
                finished_at: DateTime.utc_now(),
                exit_reason: to_string(state)
              )
            ]
          )
        end)

      unfinished_runs_with_unfinished_steps =
        Enum.map(
          [:available, :claimed, :started],
          fn state ->
            insert(:run,
              work_order: work_order,
              starting_trigger: trigger,
              dataclip: dataclip,
              state: state,
              steps: [
                build(:step,
                  job: job_1,
                  finished_at: nil,
                  exit_reason: nil
                )
              ]
            )
          end
        )

      Janitor.find_and_update_lost()

      # unfinished steps having finished runs gets updated
      for run <- finished_runs_with_unfinished_steps do
        step = hd(run.steps)
        reloaded_step = Repo.reload(step)

        assert is_nil(step.finished_at)
        assert is_nil(step.exit_reason)

        assert is_struct(reloaded_step.finished_at, DateTime)
        assert reloaded_step.exit_reason == "lost"
      end

      # finished steps having finished runs don't get updated
      for run <- finished_runs_with_finished_steps do
        step = hd(run.steps)
        reloaded_step = Repo.reload(step)

        assert step.finished_at == reloaded_step.finished_at
        assert step.exit_reason == reloaded_step.exit_reason
      end

      # unfinished steps having unfinished runs don't get updated
      for run <- unfinished_runs_with_unfinished_steps do
        step = hd(run.steps)
        reloaded_step = Repo.reload(step)

        assert step.finished_at == reloaded_step.finished_at
        assert step.exit_reason == reloaded_step.exit_reason
      end
    end

    @tag :capture_log
    test "uses started_at instead of claimed_at for timeout calculation on started runs" do
      %{triggers: [trigger]} = workflow = insert(:simple_workflow)
      dataclip = insert(:dataclip)

      work_order =
        insert(:workorder,
          workflow: workflow,
          trigger: trigger,
          dataclip: dataclip
        )

      # Simulate a run with long delay between claim and start (e.g., waiting for concurrency slot)
      # Claimed 2 minutes ago, but started only 30 seconds ago
      # With 60s timeout, should NOT be marked as lost since it only started 30s ago
      run_with_delayed_start =
        insert(:run,
          work_order: work_order,
          starting_trigger: trigger,
          dataclip: dataclip,
          state: :started,
          options: %Lightning.Runs.RunOptions{run_timeout_ms: 60_000},
          claimed_at: DateTime.utc_now() |> DateTime.add(-120, :second),
          started_at: DateTime.utc_now() |> DateTime.add(-30, :second)
        )

      # Simulate a run that should be marked as lost
      # Started 2 minutes ago with 60s timeout
      actually_lost_run =
        insert(:run,
          work_order: work_order,
          starting_trigger: trigger,
          dataclip: dataclip,
          state: :started,
          options: %Lightning.Runs.RunOptions{run_timeout_ms: 60_000},
          claimed_at: DateTime.utc_now() |> DateTime.add(-120, :second),
          started_at: DateTime.utc_now() |> DateTime.add(-120, :second)
        )

      Janitor.find_and_update_lost()

      # Run with delayed start should NOT be lost (started_at is used)
      reloaded_delayed = Repo.get(Run, run_with_delayed_start.id)
      assert reloaded_delayed.state == :started

      # Run that actually timed out should be lost
      reloaded_lost = Repo.get(Run, actually_lost_run.id)
      assert reloaded_lost.state == :lost
    end

    @tag :capture_log
    test "uses claimed_at for timeout calculation on claimed-only runs" do
      %{triggers: [trigger]} = workflow = insert(:simple_workflow)
      dataclip = insert(:dataclip)

      work_order =
        insert(:workorder,
          workflow: workflow,
          trigger: trigger,
          dataclip: dataclip
        )

      # Run claimed 2 minutes ago but never started (stuck worker)
      # Should be marked as lost based on claimed_at
      stuck_claimed_run =
        insert(:run,
          work_order: work_order,
          starting_trigger: trigger,
          dataclip: dataclip,
          state: :claimed,
          options: %Lightning.Runs.RunOptions{run_timeout_ms: 60_000},
          claimed_at: DateTime.utc_now() |> DateTime.add(-120, :second),
          started_at: nil
        )

      Janitor.find_and_update_lost()

      # Stuck claimed run should be marked as lost
      reloaded = Repo.get(Run, stuck_claimed_run.id)
      assert reloaded.state == :lost
      assert reloaded.error_type == "LostAfterClaim"
    end

    @tag :capture_log
    test "handles already completed runs gracefully without marking as lost" do
      %{triggers: [trigger]} = workflow = insert(:simple_workflow)
      dataclip = insert(:dataclip)

      work_order =
        insert(:workorder,
          workflow: workflow,
          trigger: trigger,
          dataclip: dataclip
        )

      # Create a run that would appear lost by timeout, but is already completed
      # This simulates a race condition where worker completed between query and update
      completed_run =
        insert(:run,
          work_order: work_order,
          starting_trigger: trigger,
          dataclip: dataclip,
          state: :success,
          options: %Lightning.Runs.RunOptions{run_timeout_ms: 60_000},
          claimed_at: DateTime.utc_now() |> DateTime.add(-120, :second),
          started_at: DateTime.utc_now() |> DateTime.add(-120, :second),
          finished_at: DateTime.utc_now()
        )

      Janitor.find_and_update_lost()

      # Should remain in success state, not be overwritten to lost
      reloaded = Repo.get(Run, completed_run.id)
      assert reloaded.state == :success
      refute reloaded.error_type == "LostAfterStart"
    end

    @tag :capture_log
    test "continues processing other runs when one fails to mark as lost" do
      %{triggers: [trigger]} = workflow = insert(:simple_workflow)
      dataclip = insert(:dataclip)

      work_order =
        insert(:workorder,
          workflow: workflow,
          trigger: trigger,
          dataclip: dataclip
        )

      # First lost run
      lost_run_1 =
        insert(:run,
          work_order: work_order,
          starting_trigger: trigger,
          dataclip: dataclip,
          state: :started,
          options: %Lightning.Runs.RunOptions{run_timeout_ms: 60_000},
          claimed_at: DateTime.utc_now() |> DateTime.add(-120, :second),
          started_at: DateTime.utc_now() |> DateTime.add(-120, :second)
        )

      # Second lost run
      lost_run_2 =
        insert(:run,
          work_order: work_order,
          starting_trigger: trigger,
          dataclip: dataclip,
          state: :started,
          options: %Lightning.Runs.RunOptions{run_timeout_ms: 60_000},
          claimed_at: DateTime.utc_now() |> DateTime.add(-120, :second),
          started_at: DateTime.utc_now() |> DateTime.add(-120, :second)
        )

      Janitor.find_and_update_lost()

      # Both runs should be marked as lost
      reloaded_1 = Repo.get(Run, lost_run_1.id)
      reloaded_2 = Repo.get(Run, lost_run_2.id)

      assert reloaded_1.state == :lost
      assert reloaded_2.state == :lost
    end
  end
end
