defmodule Lightning.UsageTracking.RunServiceTest do
  use Lightning.DataCase

  alias Lightning.Run
  alias Lightning.UsageTracking.RunService

  require Run

  @date ~D[2024-02-05]
  @finished_at ~U[2024-02-05 12:11:10Z]
  @other_finished_at ~U[2024-02-04 12:11:10Z]

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
