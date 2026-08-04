defmodule Lightning.Workflows.HealthTest do
  use Lightning.DataCase, async: true

  import Lightning.Factories

  alias Lightning.Workflows.Health

  setup do
    project = insert(:project)
    workflow = insert(:workflow, project: project)
    trigger = insert(:trigger, workflow: workflow, type: :webhook)
    dataclip = insert(:dataclip, project: project)

    fetch = insert(:job, workflow: workflow, name: "fetch")
    transform = insert(:job, workflow: workflow, name: "transform")

    to = DateTime.utc_now()
    from = DateTime.add(to, -24, :hour)

    %{
      workflow: workflow,
      trigger: trigger,
      dataclip: dataclip,
      fetch: fetch,
      transform: transform,
      from: from,
      to: to
    }
  end

  describe "outcomes/3" do
    test "splits finished runs into success and failure", ctx do
      run(ctx, :success)
      run(ctx, :success)
      run(ctx, :failed)
      run(ctx, :crashed)

      assert %{
               total: 4,
               pending: 0,
               success: 2,
               failed: 2,
               success_rate: 50.0,
               failure_rate: 50.0
             } = Health.outcomes(ctx.workflow, ctx.from, ctx.to)
    end

    test "keeps in-flight runs out of the success rate", ctx do
      run(ctx, :success)
      run(ctx, :started)

      # The started run counts toward the total but must not drag the rate
      # down — it has not failed, it has not finished.
      assert %{total: 2, pending: 1, success: 1, success_rate: 100.0} =
               Health.outcomes(ctx.workflow, ctx.from, ctx.to)
    end

    test "ignores runs outside the window", ctx do
      run(ctx, :success)
      run(ctx, :failed, inserted_at: DateTime.add(ctx.to, -48, :hour))

      assert %{total: 1, success: 1, failed: 0} =
               Health.outcomes(ctx.workflow, ctx.from, ctx.to)
    end

    test "reports zeroes rather than dividing by zero when empty", ctx do
      assert %{total: 0, success_rate: +0.0, failure_rate: +0.0} =
               Health.outcomes(ctx.workflow, ctx.from, ctx.to)
    end
  end

  describe "failure_breakdown/3" do
    test "groups failures by run state, most common first", ctx do
      for _ <- 1..3, do: run(ctx, :failed)
      run(ctx, :crashed)
      run(ctx, :success)

      assert %{
               total: 4,
               reasons: [
                 %{state: :failed, count: 3, percentage: 75.0},
                 %{state: :crashed, count: 1, percentage: 25.0}
               ]
             } = Health.failure_breakdown(ctx.workflow, ctx.from, ctx.to)
    end
  end

  describe "steps_with_failures/3" do
    test "attributes step failures to their job", ctx do
      run(ctx, :failed, steps: [{ctx.fetch, "success"}, {ctx.transform, "fail"}])
      run(ctx, :failed, steps: [{ctx.fetch, "fail"}])

      assert %{total: 2, unattributed: 0, steps: steps} =
               Health.steps_with_failures(ctx.workflow, ctx.from, ctx.to)

      # Both jobs failed once, so their relative order is not meaningful.
      assert Enum.sort_by(steps, & &1.job) == [
               %{job: "fetch", count: 1, attributed: true},
               %{job: "transform", count: 1, attributed: true}
             ]
    end

    test "reports failures that never reached a step separately", ctx do
      run(ctx, :crashed, steps: [])
      run(ctx, :failed, steps: [{ctx.fetch, "fail"}])

      assert %{total: 2, unattributed: 1, steps: steps} =
               Health.steps_with_failures(ctx.workflow, ctx.from, ctx.to)

      # The unattributed row is marked structurally; the client supplies the
      # wording, so no display string crosses the wire.
      assert %{job: nil, count: 1, attributed: false} in steps
    end

    test "does not count successful steps", ctx do
      run(ctx, :success, steps: [{ctx.fetch, "success"}])

      assert %{total: 0, unattributed: 0, steps: []} =
               Health.steps_with_failures(ctx.workflow, ctx.from, ctx.to)
    end
  end

  describe "volume_over_time/3" do
    test "fills empty buckets so gaps stay visible", ctx do
      run(ctx, :success)

      %{bucket_seconds: seconds, buckets: buckets} =
        Health.volume_over_time(ctx.workflow, ctx.from, ctx.to)

      assert seconds == 7200
      assert length(buckets) > 1
      assert Enum.any?(buckets, &(&1.runs == 1))
      assert Enum.any?(buckets, &(&1.runs == 0))
    end

    test "counts failures within each bucket", ctx do
      run(ctx, :failed)
      run(ctx, :success)

      %{buckets: buckets} =
        Health.volume_over_time(ctx.workflow, ctx.from, ctx.to)

      assert Enum.sum(Enum.map(buckets, & &1.runs)) == 2
      assert Enum.sum(Enum.map(buckets, & &1.failed)) == 1
    end
  end

  describe "response_time/3" do
    test "reports percentiles and a duration histogram", ctx do
      run(ctx, :success, duration: 0.5)
      run(ctx, :success, duration: 3.0)
      run(ctx, :success, duration: 90.0)

      result = Health.response_time(ctx.workflow, ctx.from, ctx.to)

      assert result.sampled == 3
      assert result.p50 == 3.0
      assert result.max == 90.0

      assert Enum.map(result.histogram, & &1.runs) == [1, 0, 1, 0, 0, 0, 1]
    end

    test "skips runs that have not finished", ctx do
      run(ctx, :started)

      assert %{sampled: 0, p50: nil, max: nil} =
               Health.response_time(ctx.workflow, ctx.from, ctx.to)
    end
  end

  describe "triage/3" do
    test "groups step failures by step and error type", ctx do
      for _ <- 1..2 do
        run(ctx, :failed, steps: [{ctx.transform, "fail", "RuntimeError"}])
      end

      assert [
               %{
                 exit_reason: "fail",
                 error_type: "RuntimeError",
                 job: "transform",
                 runs: 2,
                 blame: :user,
                 message: nil
               }
             ] = Health.triage(ctx.workflow, ctx.from, ctx.to)
    end

    test "includes failures that never reached a step", ctx do
      run(ctx, :crashed, steps: [], error_type: "CompileError")

      assert [
               %{
                 exit_reason: "crash",
                 error_type: "CompileError",
                 job: nil,
                 runs: 1
               }
             ] = Health.triage(ctx.workflow, ctx.from, ctx.to)
    end
  end

  describe "blame/2" do
    test "blames the platform for every way it can lose a run" do
      # These are the error types Lightning writes itself, in Runs.mark_run_lost/1.
      assert Health.blame("lost", "LostAfterStart") == :platform
      assert Health.blame("crash", "LostAfterClaim") == :platform
      assert Health.blame("fail", "UnknownReason") == :platform
      assert Health.blame("exception", nil) == :platform
    end

    test "blames a limit for anything the platform killed" do
      # Every error type the run viewer renders as a kill, so a new one added
      # by the worker lands here rather than being blamed on job code.
      for type <- ~w(OOMError TimeoutError SecurityError StateTooLargeError) do
        assert Health.blame("kill", type) == :limit, "#{type} should be a limit"
      end

      assert Health.blame("kill", "SomethingNew") == :limit
    end

    test "blames the remote system for adaptor failures" do
      assert Health.blame("fail", "AdaptorError") == :remote
    end

    test "blames the workflow's own code for everything else" do
      for type <- ~w(RuntimeError JobError ReferenceError ImportError) do
        assert Health.blame("fail", type) == :user, "#{type} should be user"
      end
    end
  end

  # Inserts one run, plus any steps it is given, at a fixed point inside the
  # window. `steps` entries are {job, exit_reason} or {job, exit_reason, type}.
  defp run(ctx, state, opts \\ []) do
    inserted_at =
      Keyword.get(opts, :inserted_at, DateTime.add(ctx.to, -1, :hour))

    duration = Keyword.get(opts, :duration)
    finished? = state not in [:available, :claimed, :started]

    finished_at =
      cond do
        not finished? ->
          nil

        duration ->
          DateTime.add(inserted_at, round(duration * 1000), :millisecond)

        true ->
          DateTime.add(inserted_at, 1, :second)
      end

    work_order =
      insert(:workorder,
        workflow: ctx.workflow,
        trigger: ctx.trigger,
        dataclip: ctx.dataclip,
        inserted_at: inserted_at,
        updated_at: inserted_at
      )

    steps =
      opts
      |> Keyword.get(:steps, [])
      |> Enum.map(fn
        {job, exit_reason} ->
          build_step(job, exit_reason, nil, inserted_at)

        {job, exit_reason, type} ->
          build_step(job, exit_reason, type, inserted_at)
      end)

    insert(:run,
      work_order: work_order,
      dataclip: ctx.dataclip,
      starting_trigger: ctx.trigger,
      state: state,
      error_type: Keyword.get(opts, :error_type),
      started_at: inserted_at,
      finished_at: finished_at,
      inserted_at: inserted_at,
      steps: steps
    )
  end

  defp build_step(job, exit_reason, error_type, at) do
    build(:step,
      job: job,
      exit_reason: exit_reason,
      error_type: error_type,
      started_at: at,
      finished_at: at,
      inserted_at: at
    )
  end
end
