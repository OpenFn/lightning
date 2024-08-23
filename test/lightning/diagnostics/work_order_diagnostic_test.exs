defmodule Lightning.Diagnostics.WorkOrderDiagnosticTest do
  use Lightning.DataCase

  alias Lightning.Diagnostics.WorkOrderDiagnostic

  describe ".new/1" do
    test "returns diagnostic for given WorkOrder" do
      work_order = insert(:workorder)

      expected_diagnostic = %{
        id: work_order.id,
        inserted_at: work_order.inserted_at
      }

      actual_diagnostic = WorkOrderDiagnostic.new(work_order)

      assert actual_diagnostic == expected_diagnostic
    end
  end
end
