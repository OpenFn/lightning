defmodule Lightning.Invocation.WorkOrderTest do
  use Lightning.DataCase, async: true

  alias Lightning.WorkOrder

  describe "changeset/2" do
    test "must have a workflow" do
      errors = WorkOrder.changeset(%WorkOrder{}, %{}) |> errors_on()

      assert errors[:workflow_id] == ["can't be blank"]
    end

    test "must have a reason" do
      errors = WorkOrder.changeset(%WorkOrder{}, %{}) |> errors_on()

      assert errors[:reason_id] == ["can't be blank"]
    end
  end
end
