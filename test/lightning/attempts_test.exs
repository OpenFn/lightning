defmodule Lightning.AttemptsTest do
  alias Lightning.WorkOrders
  use Lightning.DataCase, async: true
  import Lightning.Factories

  alias Lightning.Attempts

  describe "enqueue/1" do
    test "enqueues an attempt" do
      dataclip = insert(:dataclip)
      %{triggers: [trigger]} = workflow = insert(:simple_workflow)

      work_order =
        insert(:workorder,
          workflow: workflow,
          trigger: trigger,
          dataclip: dataclip
        )

      attempt =
        build(:attempt, work_order: work_order, starting_trigger: trigger)

      assert {:ok, queued_attempt} = Attempts.enqueue(attempt)

      assert queued_attempt.id == attempt.id
      assert queued_attempt.state == "available"
    end
  end

  describe "claim/1" do
    test "claims an attempt from the queue" do
      %{triggers: [trigger]} = workflow = insert(:simple_workflow)

      {:ok, %{attempts: [attempt]}} =
        WorkOrders.create_for(trigger,
          workflow: workflow,
          dataclip: params_with_assocs(:dataclip)
        )

      assert {:ok, [claimed]} = Attempts.claim()

      assert claimed.id == attempt.id
      assert claimed.state == "claimed"

      assert {:ok, []} = Attempts.claim()
    end

    test "claims with demand" do
      %{triggers: [trigger]} = workflow = insert(:simple_workflow)

      [attempt_1, attempt_2, attempt_3] =
        1..3
        |> Enum.map(fn _ ->
          {:ok, %{attempts: [attempt]}} =
            WorkOrders.create_for(trigger,
              workflow: workflow,
              dataclip: params_with_assocs(:dataclip)
            )

          attempt
        end)

      assert {:ok, [claimed_1, claimed_2]} = Attempts.claim(2)

      assert claimed_1.id == attempt_1.id
      assert claimed_1.state == "claimed"
      assert claimed_2.id == attempt_2.id
      assert claimed_2.state == "claimed"

      assert {:ok, [claimed_3]} = Attempts.claim(2)

      assert claimed_3.id == attempt_3.id
      assert claimed_3.state == "claimed"
    end
  end
end
