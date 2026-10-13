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

  test "walks the whole table, keeping steps a run links to and their log lines",
       context do
    # More than two windows' worth, with the linked steps' random ids falling
    # somewhere among them.
    insert_orphans(context.job, 2_500)

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

    assert :ok = perform_job(DeleteOrphanedSteps, %{})

    assert step_ids() == Enum.sort([shared.id, only_first.id, only_second.id])

    assert Repo.all(from(l in LogLine, select: l.id)) |> Enum.sort() ==
             Enum.sort(log_ids)
  end

  test "starts after the cursor it is given", context do
    [before_cursor, cursor | _after_cursor] =
      context.job |> insert_orphans(10) |> Enum.sort()

    assert :ok = perform_job(DeleteOrphanedSteps, %{"after_id" => cursor})

    assert step_ids() == [before_cursor, cursor]
  end

  test "ends the walk at an empty window without enqueuing a successor",
       context do
    insert_orphans(context.job, 3)

    Oban.Testing.with_testing_mode(:manual, fn ->
      assert :ok = perform_job(DeleteOrphanedSteps, %{})

      refute_enqueued(worker: DeleteOrphanedSteps)
    end)

    assert step_ids() == []
  end

  defp insert_orphans(job, count) do
    now = DateTime.utc_now()

    entries =
      for _ <- 1..count do
        %{
          id: Ecto.UUID.generate(),
          job_id: job.id,
          inserted_at: now,
          updated_at: now
        }
      end

    Repo.insert_all(Step, entries)

    Enum.map(entries, & &1.id)
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
