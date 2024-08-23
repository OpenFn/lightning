defmodule Lightning.DiagnosticsTest do
  use Lightning.DataCase

  alias Lightning.Diagnostics
  alias Lightning.Diagnostics.WorkOrderDiagnostic

  describe "workorders/3" do
    test "diagnostics for Workflow Work Orders inserted within period" do
      inclusive_starts_at = ~U[2024-08-23 06:00:00Z]
      exclusive_ends_at = ~U[2024-08-23 06:30:00Z]

      workflow = insert(:workflow)
      other_workflow = insert(:workflow)

      _before_period_work_order =
        insert(
          :workorder,
          workflow: workflow,
          inserted_at: DateTime.add(inclusive_starts_at, -1, :second)
        )

      within_period_work_order_1 =
        insert(
          :workorder,
          workflow: workflow,
          inserted_at: inclusive_starts_at
        )
      within_period_work_order_2 =
        insert(
          :workorder,
          workflow: workflow,
          inserted_at: DateTime.add(inclusive_starts_at, 1, :second)
        )
      within_period_work_order_3 =
        insert(
          :workorder,
          workflow: workflow,
          inserted_at: DateTime.add(exclusive_ends_at, -1, :second)
        )

      _after_period_work_order =
        insert(
          :workorder,
          workflow: workflow,
          inserted_at: exclusive_ends_at
        )

      _other_workflow_work_order_within_period =
        insert(
          :workorder,
          workflow: other_workflow,
          inserted_at: DateTime.add(inclusive_starts_at, 1, :second)
        )

      expected_diagnostics = [
        WorkOrderDiagnostic.new(within_period_work_order_1),
        WorkOrderDiagnostic.new(within_period_work_order_2),
        WorkOrderDiagnostic.new(within_period_work_order_3),
      ]

      actual_diagnostics = 
        workflow
        |> Diagnostics.workorders(inclusive_starts_at, exclusive_ends_at)
        |> Enum.sort_by(& &1.inserted_at, DateTime)

      assert actual_diagnostics == expected_diagnostics
    end
  end
end
