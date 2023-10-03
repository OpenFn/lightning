defmodule Lightning.WorkOrders.QueryTest do
  use Lightning.DataCase

  alias Lightning.WorkOrders.Query

  import Lightning.Factories

  describe "state_for/1" do
    test "when the attempt is the only one" do
      dataclip = insert(:dataclip)
      %{triggers: [trigger]} = workflow = insert(:simple_workflow)

      work_order = insert(:workorder, workflow: workflow, dataclip: dataclip)

      first_attempt =
        insert(:attempt,
          work_order: work_order,
          dataclip: dataclip,
          starting_trigger: trigger
        )

      assert Query.state_for(first_attempt) |> Repo.one() == :pending

      Repo.update(change(first_attempt, state: :claimed))

      second_attempt =
        insert(:attempt,
          work_order: work_order,
          dataclip: dataclip,
          starting_trigger: trigger
        )

      assert Query.state_for(second_attempt) |> Repo.one() == :pending

      Repo.update(change(first_attempt, state: :success))

      assert Query.state_for(second_attempt) |> Repo.one() == :pending

      Repo.update(change(second_attempt, state: :failed))

      assert Query.state_for(second_attempt) |> Repo.one() == :failed
    end
  end
end
