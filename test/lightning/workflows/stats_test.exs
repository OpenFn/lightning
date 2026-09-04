defmodule Lightning.Workflows.StatsTest do
  use Lightning.DataCase, async: true

  import Lightning.Factories

  alias Lightning.Workflows.Snapshot
  alias Lightning.Workflows.Stats
  alias Lightning.Workflows.Workflow
  alias Lightning.WorkOrder

  setup do
    workflow = insert(:simple_workflow)

    %{workflow: workflow, trigger: hd(workflow.triggers)}
  end

  defp work_order(workflow, trigger, attrs) do
    insert(
      :workorder,
      Keyword.merge(
        [
          workflow: workflow,
          trigger: trigger,
          dataclip: insert(:dataclip),
          state: :success
        ],
        attrs
      )
    )
  end

  # A work order carrying one run in the same state — what `state_for/1`
  # produces, and the shape almost every test here needs. States a run can't be
  # in (`:pending`, `:running`, `:rejected`) go through `work_order/3` instead.
  defp insert_run(workflow, trigger, state, days_ago \\ 0) do
    work_order =
      work_order(workflow, trigger,
        state: state,
        last_activity: days_ago(days_ago)
      )

    insert(:run,
      work_order: work_order,
      starting_trigger: trigger,
      dataclip: insert(:dataclip),
      state: state
    )
  end

  defp days_ago(days), do: DateTime.add(DateTime.utc_now(), -days, :day)

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

  # The window is anchored on `last_activity`, not `inserted_at`, so an old work
  # order someone retried today is counted as the work it currently is.
  test "counts an old work order that was active inside the window", %{
    workflow: workflow,
    trigger: trigger
  } do
    work_order(workflow, trigger,
      state: :failed,
      inserted_at: days_ago(60),
      last_activity: days_ago(1)
    )

    assert %{failed: 1} = Stats.outcomes(workflow).counts
  end

  test "counts every final state separately and skips work still in flight", %{
    workflow: workflow,
    trigger: trigger
  } do
    for state <- [:success, :success, :failed, :crashed, :cancelled, :lost] do
      insert_run(workflow, trigger, state)
    end

    work_order(workflow, trigger, state: :rejected)

    for state <- [:pending, :running] do
      work_order(workflow, trigger, state: state)
    end

    assert Stats.outcomes(workflow).counts == %{
             success: 2,
             failed: 1,
             crashed: 1,
             cancelled: 1,
             killed: 0,
             exception: 0,
             lost: 1,
             rejected: 1
           }
  end

  # Cancelling is someone stopping the work order on purpose, so it is a
  # finished outcome the page still counts but never triages.
  test "counts a cancelled work order but does not treat it as a failure", %{
    workflow: workflow,
    trigger: trigger
  } do
    insert_run(workflow, trigger, :cancelled)

    assert %{cancelled: 1, failed: 0} = Stats.outcomes(workflow).counts
    assert %{signatures: []} = Stats.failure_signatures(workflow)
  end

  # The review comment this whole unit change is for: retrying a failure until
  # it works has to make the page's failure count fall, and only a work order's
  # state can fall — the failed run stays failed forever.
  test "counts a work order retried to success once, as a success", %{
    workflow: workflow,
    trigger: trigger
  } do
    work_order = work_order(workflow, trigger, state: :success)

    for state <- [:failed, :success] do
      insert(:run,
        work_order: work_order,
        starting_trigger: trigger,
        dataclip: insert(:dataclip),
        state: state
      )
    end

    assert %{success: 1, failed: 0} = Stats.outcomes(workflow).counts
    assert %{signatures: []} = Stats.failure_signatures(workflow)
  end

  test "ignores work orders belonging to another workflow", %{
    workflow: workflow,
    trigger: trigger
  } do
    other = insert(:simple_workflow)
    insert_run(other, hd(other.triggers), :failed)
    insert_run(workflow, trigger, :success)

    assert %{success: 1, failed: 0} = Stats.outcomes(workflow).counts
  end

  test "reports zeroes for a workflow with no work orders", %{
    workflow: workflow
  } do
    assert Stats.outcomes(workflow).counts ==
             Map.new(WorkOrder.final_states(), &{&1, 0})
  end

  # The 30 s TTL is what snaps the rolling window and dedupes a burst of viewers
  # onto one query. Entries key on the workflow, so this cannot leak between
  # tests.
  test "serves a repeat call from the cache rather than requerying", %{
    workflow: workflow,
    trigger: trigger
  } do
    insert_run(workflow, trigger, :success)
    first = Stats.outcomes(workflow)

    insert_run(workflow, trigger, :failed)

    assert Stats.outcomes(workflow) == first
  end

  describe "failure_signatures/2" do
    defp failed_run(workflow, trigger, attrs, steps \\ []) do
      {wo_attrs, run_attrs} = Keyword.split(attrs, [:last_activity])
      state = Keyword.get(run_attrs, :state, :failed)

      work_order = work_order(workflow, trigger, [state: state] ++ wo_attrs)

      insert(
        :run,
        Keyword.merge(
          [
            work_order: work_order,
            starting_trigger: trigger,
            dataclip: insert(:dataclip),
            state: state,
            steps: steps
          ],
          run_attrs
        )
      )
    end

    # The signature reads the job's name and adaptor off the snapshot the step
    # ran against, so the step has to carry the workflow's own snapshot rather
    # than the unrelated one `step_factory` builds. Resolved per step, not in
    # `setup`, because `two_jobs/1` adds a job after the workflow is inserted.
    defp step(job, attrs) do
      build(
        :step,
        Keyword.merge(
          [
            job: job,
            snapshot: current_snapshot(job),
            input_dataclip: build(:dataclip),
            started_at: nil
          ],
          attrs
        )
      )
    end

    defp current_snapshot(job) do
      workflow = Repo.get!(Workflow, job.workflow_id)

      Snapshot.get_current_for(workflow) ||
        workflow |> Snapshot.create() |> elem(1)
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

    # The signature describes the run as it happened. Renaming the job or
    # bumping its adaptor afterwards must not relabel history — matching a
    # signature on the live adaptor would report a version that never ran.
    test "names the job as its snapshot recorded it, not as it is now", %{
      workflow: workflow,
      trigger: trigger
    } do
      job = hd(workflow.jobs)

      failed_run(workflow, trigger, [], [
        step(job, exit_reason: "fail", error_type: "RuntimeError")
      ])

      job
      |> Ecto.Changeset.change(%{
        name: "Renamed",
        adaptor: "@openfn/language-http@9.9.9"
      })
      |> Repo.update!()

      assert %{signatures: [signature]} = Stats.failure_signatures(workflow)

      assert signature.step_name == job.name
      assert signature.adaptor == job.adaptor
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

    # A rejected work order has no run and no step to read a signature off, so
    # the label is fixed rather than derived — and it still has to appear, or
    # the rows stop summing to the failure total the donuts draw.
    test "names a rejected work order without a run or a step", %{
      workflow: workflow,
      trigger: trigger
    } do
      work_order(workflow, trigger, state: :rejected)

      assert %{signatures: [signature]} = Stats.failure_signatures(workflow)

      assert signature == %{
               count: 1,
               exit_reason: "rejected",
               error_type: "RunLimitExceeded",
               step_name: nil,
               adaptor: nil
             }
    end

    test "groups matching work orders and sorts the heaviest first", %{
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

    # Otherwise a work order that was retried and failed again would be counted
    # twice, and the rows would sum past the failure total the donuts draw. The
    # latest run is the one whose completion set the work order's state, so it
    # is the one that gets to speak for it.
    test "attributes a retried work order to its latest run", %{
      workflow: workflow,
      trigger: trigger
    } do
      [job_a, job_b] = two_jobs(workflow)
      now = DateTime.utc_now()

      work_order = work_order(workflow, trigger, state: :failed)

      run = fn job, error_type, finished_at ->
        insert(:run,
          work_order: work_order,
          starting_trigger: trigger,
          dataclip: insert(:dataclip),
          state: :failed,
          finished_at: finished_at,
          steps: [step(job, exit_reason: "fail", error_type: error_type)]
        )
      end

      run.(job_a, "FirstAttempt", DateTime.add(now, -60))
      run.(job_b, "Retry", now)

      assert %{signatures: [signature]} = Stats.failure_signatures(workflow)
      assert %{count: 1, error_type: "Retry", step_name: name} = signature
      assert name == job_b.name
    end

    # Otherwise a run that failed twice would be counted twice.
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

    test "ignores steps that succeeded and work orders that succeeded", %{
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

    test "skips work orders outside the window and other workflows", %{
      workflow: workflow,
      trigger: trigger
    } do
      other = insert(:simple_workflow)
      failed_run(other, hd(other.triggers), error_type: "Elsewhere")

      failed_run(workflow, trigger,
        error_type: "TooOld",
        last_activity: days_ago(31)
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

  describe "invalidate/1" do
    test "drops every slice and window the workflow has cached", ctx do
      %{workflow: workflow, trigger: trigger} = ctx
      insert_run(workflow, trigger, :failed)

      # Two windows, so this fails the moment `invalidate/1` goes back to
      # deleting a hardcoded list of keys.
      Stats.outcomes(workflow)
      Stats.outcomes(workflow, 7)
      Stats.failure_signatures(workflow)

      other = insert(:simple_workflow)
      Stats.outcomes(other)

      Stats.invalidate(workflow.id)

      assert {:ok, nil} =
               Cachex.get(:workflow_stats, {:outcomes, workflow.id, 30})

      assert {:ok, nil} =
               Cachex.get(:workflow_stats, {:outcomes, workflow.id, 7})

      assert {:ok, nil} =
               Cachex.get(:workflow_stats, {:failures, workflow.id, 30})

      # Another workflow's numbers did not change, so its cache should not have
      # been swept up in the scan.
      assert {:ok, %{counts: _}} =
               Cachex.get(:workflow_stats, {:outcomes, other.id, 30})
    end
  end
end
