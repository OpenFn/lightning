defmodule Lightning.WorkOrders.CancelManyWorkOrdersJobTest do
  use Lightning.DataCase, async: true

  import Lightning.Factories

  alias Lightning.WorkOrders.CancelManyWorkOrdersJob

  describe "perform/1" do
    test "cancels available runs for the given work orders" do
      trigger = build(:trigger, type: :webhook)

      workflow =
        build(:workflow)
        |> with_trigger(trigger)
        |> insert()

      trigger = Repo.reload!(trigger)
      snapshot = Lightning.Workflows.Snapshot.build(workflow) |> Repo.insert!()

      wo =
        insert(:workorder,
          workflow: workflow,
          snapshot: snapshot,
          trigger: trigger,
          dataclip: insert(:dataclip),
          state: :pending
        )

      run =
        insert(:run,
          work_order: wo,
          starting_trigger: trigger,
          dataclip: insert(:dataclip),
          snapshot: snapshot,
          state: :available
        )

      assert :ok =
               perform_job(CancelManyWorkOrdersJob, %{
                 work_order_ids: [wo.id],
                 project_id: workflow.project_id
               })

      assert Repo.reload!(run).state == :cancelled
    end

    test "handles work orders with no available runs" do
      assert :ok =
               perform_job(CancelManyWorkOrdersJob, %{
                 work_order_ids: [Ecto.UUID.generate()],
                 project_id: Ecto.UUID.generate()
               })
    end
  end
end
