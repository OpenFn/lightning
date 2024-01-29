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

      max_run_duration =
        Application.get_env(:lightning, :max_run_duration_seconds)

      grace_period = Lightning.Config.grace_period()
      assert grace_period == max_run_duration * 0.2
      cutoff_age_in_seconds = (grace_period + max_run_duration) |> trunc()

      run_to_be_marked_lost =
        insert(:run,
          work_order: work_order,
          starting_trigger: trigger,
          dataclip: dataclip,
          state: :claimed,
          claimed_at:
            DateTime.add(now, -cutoff_age_in_seconds)
            |> DateTime.add(-2)
        )

      _crashed_but_NOT_lost =
        insert(:run,
          work_order: work_order,
          starting_trigger: trigger,
          dataclip: dataclip,
          state: :crashed,
          claimed_at:
            DateTime.add(now, -cutoff_age_in_seconds)
            |> DateTime.add(-2)
        )

      _another_run =
        insert(:run,
          work_order: work_order,
          starting_trigger: trigger,
          dataclip: dataclip,
          state: :claimed,
          claimed_at:
            DateTime.add(now, -cutoff_age_in_seconds)
            |> DateTime.add(2)
        )

      lost_runs =
        Query.lost(now)
        |> Repo.all()
        |> Enum.map(fn att -> att.id end)

      assert lost_runs == [run_to_be_marked_lost.id]
    end
  end
end
