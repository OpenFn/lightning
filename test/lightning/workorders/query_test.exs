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

    test "when the run is the only one", context do
      first_run =
        insert(:run,
          work_order: context.work_order,
          dataclip: context.dataclip,
          starting_trigger: context.trigger
        )

      assert Query.state_for(first_run) |> Repo.one() == %{state: "pending"}

      Repo.update(change(first_run, state: :claimed))

      assert Query.state_for(first_run) |> Repo.one() == %{state: "pending"}

      Repo.update(change(first_run, state: :started))

      assert Query.state_for(first_run) |> Repo.one() == %{state: "running"}

      for state <- [:success, :failed, :killed, :crashed] do
        Repo.update(change(first_run, state: state))

        assert Query.state_for(first_run) |> Repo.one() == %{
                 state: state |> to_string()
               }
      end
    end

    test "when there are more than one run", context do
      [_, _, third_run] =
        [:success, :started, :available]
        |> Enum.map(fn state ->
          insert(:run,
            work_order: context.work_order,
            dataclip: context.dataclip,
            starting_trigger: context.trigger,
            state: state
          )
        end)

      # Running wins over pending.
      assert %{state: "running"} = Query.state_for(third_run) |> Repo.one()
    end
  end
end
