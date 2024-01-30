defmodule Lightning.Runs.QueueTest do
  use Lightning.DataCase, async: true

  alias Lightning.Runs.Queue
  import Lightning.Factories

  describe "dequeue" do
    test "deletes the run and any associated run steps" do
      run_1 = insert_run()
      run_2 = insert_run()

      _run_step_1_1 = insert_run_step(run_1)
      _run_step_1_2 = insert_run_step(run_1)
      run_step_2 = insert_run_step(run_2)

      Queue.dequeue(run_1)

      assert only_record_for_type?(run_2)

      assert only_record_for_type?(run_step_2)
    end

    test "deletes associated LogLine records" do
      run_1 = build_list(2, :log_line) |> insert_run()

      run_2 = insert_run()
      log_line_2_1 = insert(:log_line, run: run_2)

      Queue.dequeue(run_1)

      assert only_record_for_type?(log_line_2_1)
    end

    defp insert_run(log_lines \\ []) do
      insert(:run,
        created_by: build(:user),
        work_order: build(:workorder),
        dataclip: build(:dataclip),
        starting_job: build(:job),
        log_lines: log_lines
      )
    end

    defp insert_run_step(run) do
      insert(:run_step, run: run, step: build(:step))
    end
  end
end
