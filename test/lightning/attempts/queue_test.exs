defmodule Lightning.Attempts.QueueTest do
  use Lightning.DataCase, async: true

  alias Lightning.Attempts.Queue
  import Lightning.Factories

  describe "dequeue" do
    test "deletes the attempt and any associated attempt runs" do
      attempt_1 = insert_attempt()
      attempt_2 = insert_attempt()

      Queue.dequeue(attempt_1)

      assert only_record_for_type?(attempt_2)
    end

    test "indicates if the operation was successful" do
      attempt_1 = insert_attempt()
      _attempt_2 = insert_attempt()

      {:ok, %Lightning.Attempt{id: id}} = Queue.dequeue(attempt_1)

      assert id == attempt_1.id
    end

    defp insert_attempt do
      insert(:attempt,
        created_by: build(:user),
        work_order: build(:workorder),
        dataclip: build(:dataclip),
        starting_job: build(:job)
      )
    end
  end
end
