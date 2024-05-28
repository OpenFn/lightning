defmodule Lightning.Runs.QueryTest do
  use Lightning.DataCase, async: true

  alias Lightning.Runs.Query

  import Lightning.Factories

  describe "lost/1" do
    test "returns only those runs which were claimed before the earliest
    allowable claim date and remain unfinished" do
      dataclip = insert(:dataclip)
      %{triggers: [trigger]} = workflow = insert(:simple_workflow)

      work_order =
        insert(:workorder,
          workflow: workflow,
          trigger: trigger,
          dataclip: dataclip
        )

      now = DateTime.utc_now()

      default_max_run_duration =
        Application.get_env(:lightning, :max_run_duration_seconds)

      grace_period = Lightning.Config.grace_period()
      default_max = grace_period + default_max_run_duration

      run_to_be_marked_lost =
        insert(:run,
          work_order: work_order,
          starting_trigger: trigger,
          dataclip: dataclip,
          state: :claimed,
          claimed_at: DateTime.add(now, -(default_max + 2))
        )

      _crashed_but_NOT_lost =
        insert(:run,
          work_order: work_order,
          starting_trigger: trigger,
          dataclip: dataclip,
          state: :crashed,
          claimed_at: DateTime.add(now, -(default_max + 2))
        )

      _another_run =
        insert(:run,
          work_order: work_order,
          starting_trigger: trigger,
          dataclip: dataclip,
          state: :claimed,
          claimed_at: DateTime.add(now, 0)
        )

      _an_old_run_with_a_long_timeout =
        insert(:run,
          work_order: work_order,
          starting_trigger: trigger,
          dataclip: dataclip,
          state: :claimed,
          options: %Lightning.Runs.RunOptions{
            # set via default to milliseconds, plus 5000 extra milliseconds
            run_timeout_ms: default_max * 1000 + 5000
          },
          claimed_at: DateTime.add(now, -(default_max + 2))
        )

      lost_runs =
        Query.lost()
        |> Repo.all()
        |> Enum.map(fn run -> run.id end)

      assert lost_runs == [run_to_be_marked_lost.id]
    end
  end
end
