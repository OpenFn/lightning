defmodule Lightning.Invocation.DeleteOrphanedStepsTest do
  use Lightning.DataCase, async: true

  import Ecto.Query
  import Lightning.Factories

  alias Lightning.Invocation.DeleteOrphanedSteps
  alias Lightning.Invocation.LogLine
  alias Lightning.Invocation.Step

  setup do
    %{triggers: [trigger], jobs: [job | _]} =
      workflow = insert(:simple_workflow)

    %{workflow: workflow, trigger: trigger, job: job}
  end

  test "deletes every step that no run links to", %{job: job} do
    # More than one batch of 100.
    insert_list(250, :step, job: job)

    assert :ok = perform_job(DeleteOrphanedSteps, %{})

    assert step_ids() == []
  end

  test "keeps steps a run links to, and their log lines", context do
    shared = insert(:step, job: context.job)
    only_first = insert(:step, job: context.job)
    only_second = insert(:step, job: context.job)

    first_run = insert_run(context, [shared, only_first])
    second_run = insert_run(context, [shared, only_second])

    log_ids =
      for {step, run} <- [
            {shared, first_run},
            {only_first, first_run},
            {only_second, second_run}
          ] do
        insert(:log_line, step: step, run: run).id
      end

    insert_list(3, :step, job: context.job)

    assert :ok = perform_job(DeleteOrphanedSteps, %{})

    assert step_ids() == Enum.sort([shared.id, only_first.id, only_second.id])

    assert Repo.all(from(l in LogLine, select: l.id)) |> Enum.sort() ==
             Enum.sort(log_ids)
  end

  test "running it again changes nothing", context do
    linked = insert(:step, job: context.job)
    insert_run(context, [linked])
    insert_list(3, :step, job: context.job)

    assert :ok = perform_job(DeleteOrphanedSteps, %{})
    assert :ok = perform_job(DeleteOrphanedSteps, %{})

    assert step_ids() == [linked.id]
  end

  defp insert_run(%{workflow: workflow, trigger: trigger}, steps) do
    %{runs: [run]} =
      insert(:workorder,
        workflow: workflow,
        trigger: trigger,
        dataclip: build(:dataclip),
        runs: [
          build(:run,
            starting_trigger: trigger,
            dataclip: build(:dataclip),
            steps: steps
          )
        ]
      )

    run
  end

  defp step_ids do
    Repo.all(from(s in Step, select: s.id, order_by: s.id))
  end
end
