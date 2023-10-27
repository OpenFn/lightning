defmodule Lightning.Attempts.QueryTest dohttps://github.com/OpenFn/Lightning/issues/1238
  use Lightning.DataCase, async: true

  alias Lightning.Attempt
  alias Lightning.Attempts.Query

  import Lightning.JobsFixtures
  import Lightning.AccountsFixtures
  import Lightning.ProjectsFixtures
  import Lightning.Factories

  describe "lost/1" do
    test "returns only those attempts which were claimed before the earliest
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
      grace_period = Lightning.Config.grace_period()

      earliest_acceptable_start = DateTime.add(now, grace_period)

      attempt_to_be_marked_lost =
        insert(:attempt,
          work_order: work_order,
          starting_trigger: trigger,
          dataclip: dataclip,
          claimed_at: DateTime.add(earliest_acceptable_start, -10)
        )

      _another_attempt =
        insert(:attempt,
          work_order: work_order,
          starting_trigger: trigger,
          dataclip: dataclip,
          claimed_at: DateTime.add(earliest_acceptable_start, 10)
        )

      lost_attempts =
        Query.lost(now)
        |> Repo.all()
        |> Enum.map(fn att -> att.id end)

      assert lost_attempts == [attempt_to_be_marked_lost.id]
    end
  end
end
