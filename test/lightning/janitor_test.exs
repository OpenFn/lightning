defmodule Lightning.JanitorTest do
  use ExUnit.Case, async: false
  alias Lightning.Janitor
  alias Lightning.Invocation
  import Lightning.Factories
  alias Lightning.Repo
  alias Lightning.Attempt

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Lightning.Repo)
  end

  describe "find_and_update_lost/0" do
    @tag :capture_log
    test "updates lost attempts and their runs" do
      %{triggers: [trigger]} = workflow = insert(:simple_workflow)
      dataclip = insert(:dataclip)

      work_order =
        insert(:workorder,
          workflow: workflow,
          trigger: trigger,
          dataclip: dataclip
        )

      lost_attempt =
        insert(:attempt,
          work_order: work_order,
          starting_trigger: trigger,
          dataclip: dataclip,
          state: :started,
          claimed_at: DateTime.utc_now() |> DateTime.add(-3600)
        )

      unfinished_run =
        insert(:run,
          attempts: [lost_attempt],
          finished_at: nil,
          exit_reason: nil
        )

      Janitor.find_and_update_lost()

      reloaded_attempt = Repo.get(Attempt, lost_attempt.id)
      reloaded_run = Repo.get(Invocation.Run, unfinished_run.id)

      assert reloaded_attempt.state == :lost
      assert reloaded_run.exit_reason == "lost"
    end
  end
end
