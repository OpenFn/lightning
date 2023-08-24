defmodule Lightning.AttemptsTest do
  use Lightning.DataCase, async: true
  import Lightning.Factories

  alias Lightning.Attempts

  describe "enqueue/1" do
    test "enqueues an attempt" do
      trigger = build(:trigger, type: :webhook)

      workflow = insert(:simple_workflow)

      reason =
        insert(:reason,
          type: trigger.type,
          trigger: trigger |> Repo.reload()
        )

      work_order = insert(:workorder, workflow: workflow, reason: reason)

      attempt = build(:attempt, work_order: work_order, reason: reason)

      assert {:ok, queued_attempt} = Attempts.enqueue(attempt)

      assert queued_attempt.id == attempt.id
    end
  end

  describe "claim/1" do
    test "claims an attempt from the queue" do
      trigger = build(:trigger, type: :webhook)

      workflow = insert(:simple_workflow)

      reason =
        insert(:reason,
          type: trigger.type,
          trigger: trigger |> Repo.reload()
        )

      work_order = insert(:workorder, workflow: workflow, reason: reason)

      attempt = insert(:attempt, work_order: work_order, reason: reason)

      assert {:ok, [claimed]} = Attempts.claim()

      assert claimed.id == attempt.id
    end

    test "claims with demand" do
      trigger = build(:trigger, type: :webhook)

      workflow = insert(:simple_workflow)

      reason =
        insert(:reason,
          type: trigger.type,
          trigger: trigger |> Repo.reload()
        )

      work_order = insert(:workorder, workflow: workflow, reason: reason)

      [attempt_1, attempt_2 | _rest] =
        insert_list(3, :attempt, work_order: work_order, reason: reason)

      assert {:ok, [claimed_1, claimed_2]} = Attempts.claim(2)

      assert claimed_1.id == attempt_1.id
      assert claimed_2.id == attempt_2.id
    end
  end
end
