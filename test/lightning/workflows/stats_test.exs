defmodule Lightning.Workflows.StatsTest do
  use Lightning.DataCase, async: true

  import Lightning.Factories

  alias Lightning.Run
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
    assert %{signatures: []} = Stats.error_signatures(workflow)
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
    assert %{signatures: []} = Stats.error_signatures(workflow)
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

  # Freshness is the cache key's job, not the TTL's: the key carries the
  # workflow's latest `last_activity`, so nothing settling means the same key
  # and one computation, however many pods are asked.
  test "asks the same question once while nothing settles", %{
    workflow: workflow,
    trigger: trigger
  } do
    insert_run(workflow, trigger, :success)

    first = Stats.outcomes(workflow)

    assert Stats.outcomes(workflow) == first

    # Also pins the key shape, which `change_marker/1` and `cached/2` have to
    # agree on and nothing else would notice going out of step.
    assert {:ok, true} =
             Cachex.exists?(
               :workflow_stats,
               {:outcomes, workflow.id, 30, marker(workflow)}
             )

    assert cached_keys(workflow) == 1
  end

  test "recomputes once a work order settles", %{
    workflow: workflow,
    trigger: trigger
  } do
    insert_run(workflow, trigger, :success)
    assert %{success: 1, failed: 0} = Stats.outcomes(workflow).counts

    insert_run(workflow, trigger, :failed)

    assert %{success: 1, failed: 1} = Stats.outcomes(workflow).counts
  end

  # `last_activity` moves when a run starts, not only when one settles, so an
  # unfiltered marker would hand every open tab a new key, and a full
  # recompute, on every poll of a workflow with a cron.
  test "does not recompute while a work order is only running", %{
    workflow: workflow,
    trigger: trigger
  } do
    insert_run(workflow, trigger, :success)
    first = Stats.outcomes(workflow)

    work_order(workflow, trigger,
      state: :running,
      last_activity: DateTime.utc_now()
    )

    assert Stats.outcomes(workflow) == first
    assert cached_keys(workflow) == 1
  end

  # `cached/2` is private, so this drives it through `outcomes/2` with a window
  # wide enough to blow up the date arithmetic. Which failure is beside the
  # point; that it escapes as an exception, not a match error, is not.
  test "reraises a failed computation instead of matching on the error tuple",
       %{workflow: workflow} do
    assert_raise Cachex.Error, fn -> Stats.outcomes(workflow, 100_000_000) end
  end

  defp marker(workflow) do
    Lightning.Repo.one(
      from(wo in WorkOrder,
        where:
          wo.workflow_id == ^workflow.id and
            wo.state in ^WorkOrder.final_states(),
        select: max(wo.last_activity)
      )
    )
  end

  # Scoped to this workflow: the file is `async: true` against a cache shared
  # by the whole node, so a count of everything in it would be a coin toss.
  defp cached_keys(workflow) do
    query =
      Cachex.Query.build(
        where: {:==, {:element, 2, :key}, workflow.id},
        output: :key
      )

    :workflow_stats |> Cachex.stream!(query) |> Enum.count()
  end

  describe "error_signatures/2" do
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

      assert %{signatures: [signature]} = Stats.error_signatures(workflow)

      assert signature == %{
               count: 1,
               exit_reason: "fail",
               error_type: "RuntimeError",
               job_id: job.id,
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

      assert %{signatures: [signature]} = Stats.error_signatures(workflow)

      assert signature.step_name == job.name
      assert signature.adaptor == job.adaptor
    end

    # The row is keyed by `job_id`, not by the resolved name — that is what
    # keeps a job renamed mid-window as one row instead of splitting into a
    # before-rename row and an after-rename row. The label comes off the
    # newer of the two snapshots, since that is the name the job actually has
    # by the time anyone triages it.
    test "merges a job renamed mid-window into one row, labelled with the newer name",
         %{workflow: workflow, trigger: trigger} do
      job = hd(workflow.jobs)
      job_id = job.id

      failed_run(workflow, trigger, [], [
        step(job, exit_reason: "fail", error_type: "RuntimeError")
      ])

      job
      |> Ecto.Changeset.change(name: "Renamed")
      |> Repo.update!()

      # `current_snapshot/1` only creates a new snapshot when none exists for
      # the workflow's current `lock_version`, so the rename alone would still
      # resolve against the snapshot already made above. Bumping it forces a
      # second snapshot — the newer one the label tiebreak has to pick.
      workflow
      |> Ecto.Changeset.change(lock_version: workflow.lock_version + 1)
      |> Repo.update!()

      failed_run(workflow, trigger, [], [
        step(job, exit_reason: "fail", error_type: "RuntimeError")
      ])

      assert %{signatures: [signature]} = Stats.error_signatures(workflow)

      assert %{count: 2, job_id: ^job_id, step_name: "Renamed"} = signature
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

      assert %{signatures: [signature]} = Stats.error_signatures(workflow)
      assert signature.exit_reason == "lost"
      assert signature.error_type == "LostAfterStart"
      assert signature.step_name == job.name
    end

    test "renders a run that never reached a step without the step clause", %{
      workflow: workflow,
      trigger: trigger
    } do
      failed_run(workflow, trigger, state: :crashed, error_type: "CompileError")

      assert %{signatures: [signature]} = Stats.error_signatures(workflow)

      assert signature == %{
               count: 1,
               exit_reason: "crash",
               error_type: "CompileError",
               job_id: nil,
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

      assert %{signatures: [signature]} = Stats.error_signatures(workflow)

      assert signature == %{
               count: 1,
               exit_reason: "rejected",
               error_type: "RunLimitExceeded",
               job_id: nil,
               step_name: nil,
               adaptor: nil
             }
    end

    # `"" || x` returns `""` in Elixir, so an empty error type would otherwise
    # coalesce to itself instead of falling through — splitting one signature
    # into two rows that render identically and each half the count.
    test "treats an empty error type the same as a missing one", %{
      workflow: workflow,
      trigger: trigger
    } do
      job = hd(workflow.jobs)

      failed_run(workflow, trigger, [], [
        step(job, exit_reason: "fail", error_type: "")
      ])

      failed_run(workflow, trigger, [], [
        step(job, exit_reason: "fail", error_type: nil)
      ])

      assert %{signatures: [%{count: 2, error_type: nil}]} =
               Stats.error_signatures(workflow)
    end

    # And on the run's own error type, which the step falls through to: it is
    # read straight into the signature, so an empty one splits the rows there
    # instead.
    test "treats an empty error type on the run the same as a missing one", %{
      workflow: workflow,
      trigger: trigger
    } do
      failed_run(workflow, trigger, state: :crashed, error_type: "")
      failed_run(workflow, trigger, state: :crashed, error_type: nil)

      assert %{signatures: [%{count: 2, exit_reason: "crash", error_type: nil}]} =
               Stats.error_signatures(workflow)
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
               Stats.error_signatures(workflow)

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

      assert %{signatures: [signature]} = Stats.error_signatures(workflow)
      assert %{count: 1, error_type: "Retry", step_name: name} = signature
      assert name == job_b.name
    end

    # A workflow that fans out can break in more than one place at once, and
    # each break is its own thing to fix — so both are reported, and the counts
    # sum past the one work order they came from.
    test "reports every failing step of a run, not just the first", %{
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

      assert %{signatures: signatures} = Stats.error_signatures(workflow)

      assert [
               %{count: 1, error_type: "Earlier", step_name: job_a.name},
               %{count: 1, error_type: "Later", step_name: job_b.name}
             ] ==
               signatures
               |> Enum.map(&Map.take(&1, [:count, :error_type, :step_name]))
               |> Enum.sort_by(& &1.error_type)
    end

    # The same signature reaching a work order twice still describes one broken
    # work order, which is what the column counts.
    test "counts a work order once per signature it hits", %{
      workflow: workflow,
      trigger: trigger
    } do
      job = hd(workflow.jobs)

      failed_run(workflow, trigger, [], [
        step(job, exit_reason: "fail", error_type: "RuntimeError"),
        step(job, exit_reason: "fail", error_type: "RuntimeError")
      ])

      assert %{signatures: [%{count: 1, error_type: "RuntimeError"}]} =
               Stats.error_signatures(workflow)
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
               Stats.error_signatures(workflow)
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
               Stats.error_signatures(workflow)

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

      assert %{signatures: []} = Stats.error_signatures(workflow)
    end

    # Both render as `unknown`, so ungrouped the table drew two rows under one
    # React key.
    test "groups an empty error type with a missing one", %{
      workflow: workflow,
      trigger: trigger
    } do
      job = hd(workflow.jobs)

      failed_run(workflow, trigger, [], [
        step(job, exit_reason: "fail", error_type: "")
      ])

      failed_run(workflow, trigger, [], [
        step(job, exit_reason: "fail", error_type: nil)
      ])

      assert %{signatures: [signature]} = Stats.error_signatures(workflow)
      assert %{count: 2, error_type: nil} = signature
    end

    # `""` is truthy, so it won the `||` in `to_signature/2`.
    test "does not let an empty step error type mask the run's", %{
      workflow: workflow,
      trigger: trigger
    } do
      job = hd(workflow.jobs)

      failed_run(
        workflow,
        trigger,
        [state: :lost, error_type: "LostAfterStart"],
        [step(job, exit_reason: "lost", error_type: "")]
      )

      assert %{signatures: [signature]} = Stats.error_signatures(workflow)
      assert signature.error_type == "LostAfterStart"
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

  describe "runs/2" do
    # A run whose `inserted_at` we choose, on a work order active at the same
    # moment — the shape the window needs and `insert_run/4` can't give.
    defp run_at(workflow, trigger, state, at) do
      # A work order has no `:available`, so an in-flight run hangs off a
      # running one.
      wo_state = if state in WorkOrder.final_states(), do: state, else: :running

      insert(:run,
        work_order:
          work_order(workflow, trigger, state: wo_state, last_activity: at),
        starting_trigger: trigger,
        dataclip: insert(:dataclip),
        state: state,
        inserted_at: at
      )
    end

    # Written out rather than a fixed index, because the grid moves with the
    # clock: at 09:59 the last 2-hourly bucket is 08:00, at 10:01 it is 10:00.
    defp bucket_of(%{window: %{from: from}, buckets: [a, b | _]}, at) do
      DateTime.diff(at, from, :second)
      |> div(DateTime.diff(b.at, a.at, :second))
    end

    test "counts each state into the bucket its run started in", ctx do
      %{workflow: workflow, trigger: trigger} = ctx

      older = DateTime.add(DateTime.utc_now(), -5, :hour)
      newer = DateTime.add(DateTime.utc_now(), -90, :minute)

      # A hair inside a bucket, not in the next one: `extract(epoch ...)` is
      # `numeric` and casting it rounds, so the query has to floor first.
      edge =
        DateTime.utc_now()
        |> DateTime.to_unix()
        |> div(7_200)
        |> Kernel.*(7_200)
        |> DateTime.from_unix!()
        |> DateTime.add(-4, :hour)
        |> DateTime.add(-100, :millisecond)

      run_at(workflow, trigger, :failed, newer)
      run_at(workflow, trigger, :success, older)
      run_at(workflow, trigger, :success, older)
      run_at(workflow, trigger, :crashed, edge)

      assert %{buckets: buckets} = result = Stats.runs(workflow, 1)

      assert %{success: 2, failed: 0} =
               Enum.at(buckets, bucket_of(result, older))

      assert %{success: 0, failed: 1} =
               Enum.at(buckets, bucket_of(result, newer))

      assert %{crashed: 1} = Enum.at(buckets, bucket_of(result, edge))
    end

    # Boundaries on the clock, so the chart can label a bar "2am" or "Tuesday"
    # and be telling the truth. And a bar chart with holes in it is a different
    # chart, so every bucket carries every final state, zero-filled.
    test "cuts each window into clock-aligned, zero-filled buckets", ctx do
      %{workflow: workflow} = ctx

      zeroed = Map.new(Run.final_states(), &{&1, 0})

      for {days, seconds, count} <- [
            {1, 7_200, 13},
            {7, 43_200, 15},
            {30, 86_400, 31}
          ] do
        assert %{buckets: buckets, window: window} = Stats.runs(workflow, days)

        assert length(buckets) == count
        assert rem(DateTime.to_unix(window.from), seconds) == 0

        assert DateTime.compare(
                 window.from,
                 DateTime.add(window.to, -days, :day)
               ) != :gt

        assert DateTime.diff(Enum.at(buckets, 1).at, hd(buckets).at) == seconds

        for bucket <- buckets, do: assert(Map.delete(bucket, :at) == zeroed)

        # The window ends inside the last bucket, which is still filling.
        last = List.last(buckets).at
        assert DateTime.compare(last, window.to) == :lt
        assert DateTime.diff(window.to, last, :second) < seconds
      end
    end

    # Keyed without the change marker — a settle must not mint a new key.
    test "serves the same answer after a work order settles", ctx do
      %{workflow: workflow, trigger: trigger} = ctx

      run_at(workflow, trigger, :success, DateTime.utc_now())
      first = Stats.runs(workflow, 1)

      run_at(workflow, trigger, :failed, DateTime.utc_now())

      assert Stats.runs(workflow, 1) == first

      assert {:ok, true} =
               Cachex.exists?(:workflow_stats, {:runs, workflow.id, 1})
    end

    test "skips runs outside the window, in flight, or on another workflow",
         ctx do
      %{workflow: workflow, trigger: trigger} = ctx

      run_at(workflow, trigger, :success, days_ago(2))
      run_at(workflow, trigger, :available, DateTime.utc_now())

      other = insert(:simple_workflow)
      run_at(other, hd(other.triggers), :success, DateTime.utc_now())

      assert %{buckets: buckets} = Stats.runs(workflow, 1)

      assert Enum.sum_by(buckets, fn bucket ->
               bucket |> Map.delete(:at) |> Map.values() |> Enum.sum()
             end) == 0
    end
  end
end
