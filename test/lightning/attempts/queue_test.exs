defmodule Lightning.Attempts.QueueTest do
  use Lightning.DataCase, async: true

  alias Lightning.Attempts.Queue
  import Lightning.Factories

  describe "dequeue" do
    test "deletes the attempt and any associated attempt steps" do
      attempt_1 = insert_attempt()
      attempt_2 = insert_attempt()

      _attempt_step_1_1 = insert_attempt_step(attempt_1)
      _attempt_step_1_2 = insert_attempt_step(attempt_1)
      attempt_step_2 = insert_attempt_step(attempt_2)

      Queue.dequeue(attempt_1)

      assert only_record_for_type?(attempt_2)

      assert only_record_for_type?(attempt_step_2)
    end

    test "deletes associated LogLine records" do
      attempt_1 = build_list(2, :log_line) |> insert_attempt()

      attempt_2 = insert_attempt()
      log_line_2_1 = insert(:log_line, attempt: attempt_2)

      Queue.dequeue(attempt_1)

      assert only_record_for_type?(log_line_2_1)
    end

    defp insert_attempt(log_lines \\ []) do
      insert(:attempt,
        created_by: build(:user),
        work_order: build(:workorder),
        dataclip: build(:dataclip),
        starting_job: build(:job),
        log_lines: log_lines
      )
    end

    defp insert_attempt_step(attempt) do
      insert(:attempt_step, attempt: attempt, step: build(:step))
    end
  end
end
