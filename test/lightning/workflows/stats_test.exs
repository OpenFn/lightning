defmodule Lightning.Workflows.StatsTest do
  use Lightning.DataCase, async: true

  import Lightning.Factories

  alias Lightning.Workflows.Stats

  setup do
    workflow = insert(:simple_workflow)

    %{workflow: workflow, trigger: hd(workflow.triggers)}
  end

  defp insert_workorder(workflow, trigger, days_ago) do
    insert(:workorder,
      workflow: workflow,
      trigger: trigger,
      dataclip: insert(:dataclip),
      state: :success,
      inserted_at: DateTime.add(DateTime.utc_now(), -days_ago, :day)
    )
  end

  test "counts the last 30 days by default", %{
    workflow: workflow,
    trigger: trigger
  } do
    insert_workorder(workflow, trigger, 10)
    insert_workorder(workflow, trigger, 31)

    outcomes = Stats.outcomes(workflow)

    assert outcomes.counts == %{success: 1, failed: 0, pending: 0}
    assert DateTime.diff(outcomes.window.to, outcomes.window.from, :day) == 30
  end

  test "narrows both the counts and the reported window to days_back", %{
    workflow: workflow,
    trigger: trigger
  } do
    insert_workorder(workflow, trigger, 3)
    insert_workorder(workflow, trigger, 10)

    outcomes = Stats.outcomes(workflow, 7)

    assert outcomes.counts == %{success: 1, failed: 0, pending: 0}
    assert DateTime.diff(outcomes.window.to, outcomes.window.from, :day) == 7
  end

  test "buckets every non-success, non-active work order state as failed", %{
    workflow: workflow,
    trigger: trigger
  } do
    for state <- [:success, :failed, :crashed, :killed, :running, :pending] do
      insert(:workorder,
        workflow: workflow,
        trigger: trigger,
        dataclip: insert(:dataclip),
        state: state
      )
    end

    outcomes = Stats.outcomes(workflow)

    assert outcomes.counts == %{success: 1, failed: 3, pending: 2}
  end
end
