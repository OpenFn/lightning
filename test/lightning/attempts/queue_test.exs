defmodule Lightning.Attempts.QueueTest do
  use Lightning.DataCase, async: true

  alias Lightning.Attempts.Queue
  import Lightning.Factories

  describe "dequeue" do
    test "deletes the attempt and any associated attempt runs" do
      attempt_1 = insert(:attempt_with_dependencies)
      attempt_2 = insert(:attempt_with_dependencies)

      _attempt_run_1_1 = insert(:attempt_run_with_run, attempt: attempt_1)
      _attempt_run_1_2 = insert(:attempt_run_with_run, attempt: attempt_1)
      attempt_run_2 = insert(:attempt_run_with_run, attempt: attempt_2)

      Queue.dequeue(attempt_1)

      assert only_record_for_type?(attempt_2)

      assert only_record_for_type?(attempt_run_2)
    end

    test "deletes associated LogLine records" do
      attempt_1 =
        insert(:attempt_with_dependencies,
          log_lines: build_list(2, :log_line)
        )

      attempt_2 = insert(:attempt_with_dependencies)
      log_line_2_1 = insert(:log_line, attempt: attempt_2)

      Queue.dequeue(attempt_1)

      assert only_record_for_type?(log_line_2_1)
    end
  end
end
