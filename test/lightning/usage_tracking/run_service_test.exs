defmodule Lightning.UsageTracking.RunServiceTest do
  use Lightning.DataCase, async: true

  alias Lightning.Run
  alias Lightning.UsageTracking.RunService

  require Run

  @date ~D[2024-02-05]
  @finished_at ~U[2024-02-05 12:11:10Z]
  @other_finished_at ~U[2024-02-04 12:11:10Z]

  describe ".finished_runs/2" do
    test "returns the subset of runs finished on the given date" do
      finished_on_report_date = insert_finished_runs(@finished_at)
      finished_on_other_date = insert_finished_runs(@other_finished_at)
      unfinished = insert_unfinished_runs()

      run_list = finished_on_other_date ++ finished_on_report_date ++ unfinished

      assert(
        RunService.finished_runs(run_list, @date) == finished_on_report_date
      )
    end

    defp insert_finished_runs(finished_at) do
      Run.final_states()
      |> Enum.map(fn state ->
        insert(
          :run,
          state: state,
          finished_at: finished_at,
          work_order: build(:workorder),
          dataclip: build(:dataclip),
          starting_job: build(:job)
        )
      end)
    end

    defp insert_unfinished_runs do
      [:available, :claimed, :started]
      |> Enum.map(fn state ->
        insert(
          :run,
          state: state,
          work_order: build(:workorder),
          dataclip: build(:dataclip),
          starting_job: build(:job)
        )
      end)
    end
  end

  describe ".finished_steps/2" do
    test "returns all run steps that finished on report date" do
      run_1 =
        insert(
          :run,
          work_order: build(:workorder),
          dataclip: build(:dataclip),
          starting_job: build(:job)
        )

      run_2 =
        insert(
          :run,
          work_order: build(:workorder),
          dataclip: build(:dataclip),
          starting_job: build(:job)
        )

      finished_1 = insert_steps(run_1)
      finished_2 = insert_steps(run_2)

      run_1 = run_1 |> Repo.preload(:steps)
      run_2 = run_2 |> Repo.preload(:steps)

      runs = [run_1, run_2]

      expected_ids = (finished_1 ++ finished_2) |> MapSet.new(& &1.id)
      actual_ids = RunService.finished_steps(runs, @date) |> MapSet.new(& &1.id)

      assert(actual_ids == expected_ids)
    end

    defp insert_steps(run) do
      insert_step = fn ->
        insert(
          :step,
          finished_at: @finished_at,
          job: fn -> build(:job) end
        )
      end

      finished =
        insert_list(
          2,
          :run_step,
          run: run,
          step: insert_step
        )

      _finished_other =
        insert(
          :run_step,
          run: run,
          step:
            insert(
              :step,
              finished_at: @other_finished_at,
              job: build(:job)
            )
        )

      _unfinished =
        insert(
          :run_step,
          run: run,
          step:
            insert(
              :step,
              finished_at: nil,
              job: build(:job)
            )
        )

      for run_step <- finished, do: run_step.step
    end
  end

  describe "unique_jobs/2" do
    test "returns unique jobs across all steps finished on report date" do
      job_1 = insert(:job)
      job_2 = insert(:job)
      job_3 = insert(:job)
      job_4 = insert(:job)

      finished_on_date_1 = insert_step(job_1, @finished_at)
      finished_on_date_2 = insert_step(job_2, @finished_at)
      finished_on_date_3 = insert_step(job_1, @finished_at)
      finished_on_another_date = insert_step(job_3, @other_finished_at)
      unfinished = insert_step(job_4, nil)

      steps = [
        finished_on_date_1,
        finished_on_another_date,
        finished_on_date_3,
        finished_on_date_2,
        unfinished
      ]

      assert RunService.unique_jobs(steps, @date) == [job_1, job_2]
    end

    defp insert_step(job, finished_at) do
      insert(
        :run_step,
        run:
          build(
            :run,
            work_order: build(:workorder),
            starting_job: job,
            dataclip: build(:dataclip)
          ),
        step: build(:step, finished_at: finished_at, job: job)
      ).step
    end
  end
end
