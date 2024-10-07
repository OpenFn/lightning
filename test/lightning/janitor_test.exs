defmodule Lightning.JanitorTest do
  use Lightning.DataCase, async: true
  alias Lightning.Janitor
  alias Lightning.Invocation
  import Lightning.Factories
  alias Lightning.Repo
  alias Lightning.Run

  describe "forfeit_expired_claims/0" do
    test "releases runs for reclaim if they have not been started after the pull timeout plus grace" do
      dbg("eish, i don't love this. what if there was some other reason for them getting lost?")
      dbg("like, what if they did start, and did the work, and all that, but we never heard back from them because of network issues?")
      dbg("i wouldn't want to re-do the work.")
      dbg("i wish there was some way to only mark them as claimed once we know that the worker actually got the run.")
      dbg("can we check that our reply in the websocket channel was actually received by the ws-worker?")
    end
  end

  describe "find_and_update_lost/0" do
    @tag :capture_log
    test "updates lost runs and their steps" do
      %{triggers: [trigger]} = workflow = insert(:simple_workflow)
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
    end
  end
end
