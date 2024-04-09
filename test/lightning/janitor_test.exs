defmodule Lightning.JanitorTest do
  use Lightning.DataCase, async: true
  alias Lightning.Janitor
  alias Lightning.Invocation
  import Lightning.Factories
  alias Lightning.Repo
  alias Lightning.Run

  describe "find_and_update_lost/0" do
    @tag :capture_log
    test "updates lost runs and their steps" do
      %{triggers: [trigger]} = workflow = insert(:simple_workflow)
      dataclip = insert(:dataclip)

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
          claimed_at: DateTime.utc_now() |> DateTime.add(-3600)
        )

      unfinished_step =
        insert(:step,
          runs: [lost_run],
          finished_at: nil,
          exit_reason: nil
        )

      Janitor.find_and_update_lost()

      reloaded_run = Repo.get(Run, lost_run.id)
      reloaded_step = Repo.get(Invocation.Step, unfinished_step.id)

      assert reloaded_run.state == :lost
      assert reloaded_step.exit_reason == "lost"
    end
  end
end
