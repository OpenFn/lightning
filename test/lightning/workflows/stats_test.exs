defmodule Lightning.Workflows.StatsTest do
  use Lightning.DataCase, async: true

  import Lightning.Factories

  alias Lightning.Workflows.Stats

  setup do
    workflow = insert(:simple_workflow)

    %{workflow: workflow, trigger: hd(workflow.triggers)}
  end

  defp insert_run(workflow, trigger, state, days_ago \\ 0) do
    work_order =
      insert(:workorder,
        workflow: workflow,
        trigger: trigger,
        dataclip: insert(:dataclip),
        state: :success
      )

    insert(:run,
      work_order: work_order,
      starting_trigger: trigger,
      dataclip: insert(:dataclip),
      state: state,
      inserted_at: DateTime.add(DateTime.utc_now(), -days_ago, :day)
    )
  end

  test "counts the last 30 days by default", %{
    workflow: workflow,
    trigger: trigger
  } do
    insert_run(workflow, trigger, :success, 10)
    insert_run(workflow, trigger, :success, 31)

    outcomes = Stats.outcomes(workflow)

    assert outcomes.counts.success == 1
    assert DateTime.diff(outcomes.window.to, outcomes.window.from, :day) == 30
  end

  test "narrows both the counts and the reported window to days_back", %{
    workflow: workflow,
    trigger: trigger
  } do
    insert_run(workflow, trigger, :success, 3)
    insert_run(workflow, trigger, :success, 10)

    outcomes = Stats.outcomes(workflow, 7)

    assert outcomes.counts.success == 1
    assert DateTime.diff(outcomes.window.to, outcomes.window.from, :day) == 7
  end

  # Retries are the reason the page counts runs: three attempts at one inbound
  # event are three outcomes, and the failure breakdown has to name each state.
  test "counts every final state separately and skips runs still in flight", %{
    workflow: workflow,
    trigger: trigger
  } do
    for state <- [:success, :success, :failed, :crashed, :lost, :started] do
      insert_run(workflow, trigger, state)
    end

    assert Stats.outcomes(workflow).counts == %{
             success: 2,
             failed: 1,
             crashed: 1,
             cancelled: 0,
             killed: 0,
             exception: 0,
             lost: 1
           }
  end

  test "ignores runs belonging to another workflow", %{
    workflow: workflow,
    trigger: trigger
  } do
    other = insert(:simple_workflow)
    insert_run(other, hd(other.triggers), :failed)
    insert_run(workflow, trigger, :success)

    assert %{success: 1, failed: 0} = Stats.outcomes(workflow).counts
  end

  test "reports zeroes for a workflow with no runs", %{workflow: workflow} do
    assert Stats.outcomes(workflow).counts ==
             Map.new(Lightning.Run.final_states(), &{&1, 0})
  end

  describe "failure_signatures/2" do
    defp failed_run(workflow, trigger, attrs, steps \\ []) do
      work_order =
        insert(:workorder,
          workflow: workflow,
          trigger: trigger,
          dataclip: insert(:dataclip),
          state: :failed
        )

      insert(
        :run,
        Keyword.merge(
          [
            work_order: work_order,
            starting_trigger: trigger,
            dataclip: insert(:dataclip),
            state: :failed,
            steps: steps
          ],
          attrs
        )
      )
    end

    defp step(job, attrs) do
      build(
        :step,
        Keyword.merge(
          [job: job, input_dataclip: build(:dataclip), started_at: nil],
          attrs
        )
      )
    end

    test "builds a step-level signature from the step's own reason and type",
         %{workflow: workflow, trigger: trigger} do
      job = hd(workflow.jobs)

      failed_run(workflow, trigger, [], [
        step(job, exit_reason: "fail", error_type: "RuntimeError")
      ])

      assert %{signatures: [signature]} = Stats.failure_signatures(workflow)

      assert signature == %{
               count: 1,
               exit_reason: "fail",
               error_type: "RuntimeError",
               step_name: job.name,
               adaptor: job.adaptor
             }
    end

    # `mark_steps_lost/1` stamps the step's exit_reason and nothing else, so
    # the error type has to come off the run or the signature reads `lost:`.
    test "falls back to the run's error type when the step never reported one",
         %{workflow: workflow, trigger: trigger} do
      job = hd(workflow.jobs)

      failed_run(
        workflow,
        trigger,
        [state: :lost, error_type: "LostAfterStart"],
        [step(job, exit_reason: "lost", error_type: nil)]
      )

      assert %{signatures: [signature]} = Stats.failure_signatures(workflow)
      assert signature.exit_reason == "lost"
      assert signature.error_type == "LostAfterStart"
      assert signature.step_name == job.name
    end

    test "renders a run that never reached a step without the step clause", %{
      workflow: workflow,
      trigger: trigger
    } do
      failed_run(workflow, trigger, state: :crashed, error_type: "CompileError")

      assert %{signatures: [signature]} = Stats.failure_signatures(workflow)

      assert signature == %{
               count: 1,
               exit_reason: "crash",
               error_type: "CompileError",
               step_name: nil,
               adaptor: nil
             }
    end

    test "groups matching runs and sorts the heaviest signature first", %{
      workflow: workflow,
      trigger: trigger
    } do
      job = hd(workflow.jobs)

      for _ <- 1..3 do
        failed_run(workflow, trigger, [], [
          step(job, exit_reason: "fail", error_type: "RuntimeError")
        ])
      end

      failed_run(workflow, trigger, state: :crashed, error_type: "CompileError")

      assert %{signatures: [first, second]} =
               Stats.failure_signatures(workflow)

      assert %{count: 3, error_type: "RuntimeError"} = first
      assert %{count: 1, error_type: "CompileError"} = second
    end

    # Otherwise a run that failed twice would be counted twice, and the rows
    # would sum past the failure total the outcomes donut draws.
    test "attributes a run with two failed steps to the earliest one only", %{
      workflow: workflow,
      trigger: trigger
    } do
      [job_a, job_b] = two_jobs(workflow)
      now = DateTime.utc_now()

      failed_run(workflow, trigger, [], [
        step(job_b,
          exit_reason: "fail",
          error_type: "Later",
          started_at: DateTime.add(now, 5)
        ),
        step(job_a,
          exit_reason: "fail",
          error_type: "Earlier",
          started_at: now
        )
      ])

      assert %{signatures: [signature]} = Stats.failure_signatures(workflow)
      assert %{count: 1, error_type: "Earlier", step_name: name} = signature
      assert name == job_a.name
    end

    test "ignores steps that succeeded and runs that succeeded", %{
      workflow: workflow,
      trigger: trigger
    } do
      job = hd(workflow.jobs)

      # A failed run whose first step passed — the signature must describe the
      # step that broke, not the one before it.
      failed_run(workflow, trigger, [], [
        step(job, exit_reason: "success", started_at: DateTime.utc_now()),
        step(job,
          exit_reason: "fail",
          error_type: "RuntimeError",
          started_at: DateTime.add(DateTime.utc_now(), 5)
        )
      ])

      insert_run(workflow, trigger, :success)

      assert %{signatures: [%{count: 1, error_type: "RuntimeError"}]} =
               Stats.failure_signatures(workflow)
    end

    test "still finds a failing step that never stamped a start time", %{
      workflow: workflow,
      trigger: trigger
    } do
      job = hd(workflow.jobs)

      failed_run(workflow, trigger, [], [
        step(job, exit_reason: "success", started_at: DateTime.utc_now()),
        step(job, exit_reason: "fail", error_type: "RuntimeError")
      ])

      assert %{signatures: [%{error_type: "RuntimeError", step_name: name}]} =
               Stats.failure_signatures(workflow)

      assert name == job.name
    end

    test "skips runs outside the window and other workflows", %{
      workflow: workflow,
      trigger: trigger
    } do
      other = insert(:simple_workflow)
      failed_run(other, hd(other.triggers), error_type: "Elsewhere")

      failed_run(workflow, trigger,
        error_type: "TooOld",
        inserted_at: DateTime.add(DateTime.utc_now(), -31, :day)
      )

      assert %{signatures: []} = Stats.failure_signatures(workflow)
    end

    defp two_jobs(workflow) do
      case workflow.jobs do
        [job] ->
          [job, insert(:job, workflow: workflow, name: "Second job")]

        jobs ->
          Enum.take(jobs, 2)
      end
    end
  end
end
