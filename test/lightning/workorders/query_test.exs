defmodule Lightning.WorkOrders.QueryTest do
  use Lightning.DataCase

  alias Lightning.WorkOrders.Query

  import Lightning.Factories

  describe "state_for/1" do
    setup do
      dataclip = insert(:dataclip)
      %{triggers: [trigger]} = workflow = insert(:simple_workflow)

      work_order = insert(:workorder, workflow: workflow, dataclip: dataclip)

      %{work_order: work_order, trigger: trigger, dataclip: dataclip}
    end

    test "when the attempt is the only one", context do
      first_attempt =
        insert(:attempt,
          work_order: context.work_order,
          dataclip: context.dataclip,
          starting_trigger: context.trigger
        )

      assert Query.state_for(first_attempt) |> Repo.one() == :pending

      Repo.update(change(first_attempt, state: :claimed))

      assert Query.state_for(first_attempt) |> Repo.one() == :pending

      Repo.update(change(first_attempt, state: :started))

      assert Query.state_for(first_attempt) |> Repo.one() == :running

      for state <- [:success, :failed, :killed, :crashed] do
        Repo.update(change(first_attempt, state: state))

        assert Query.state_for(first_attempt) |> Repo.one() == state
      end
    end

    test "when there are more than one attempt", context do
      _first_attempt =
        insert(:attempt,
          work_order: context.work_order,
          dataclip: context.dataclip,
          starting_trigger: context.trigger,
          state: :success
        )

      _second_attempt =
        insert(:attempt,
          work_order: context.work_order,
          dataclip: context.dataclip,
          starting_trigger: context.trigger,
          state: :started
        )

      third_attempt =
        insert(:attempt,
          work_order: context.work_order,
          dataclip: context.dataclip,
          starting_trigger: context.trigger,
          state: :available
        )

      assert Query.state_for(third_attempt) |> Repo.one() == :running
    end
  end
end
