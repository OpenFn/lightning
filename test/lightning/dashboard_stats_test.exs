defmodule Lightning.DashboardStatsTest do
  @moduledoc false
  use Lightning.DataCase

  import Lightning.WorkflowsFixtures

  alias Lightning.DashboardStats
  alias Lightning.DashboardStats.WorkflowStats
  alias Lightning.DashboardStats.ProjectMetrics

  describe "get_workflow_stats/1" do
    test "returns a WorkflowStats with all data bound to last 30 days" do
      dataclip = insert(:dataclip)

      %{id: workflow_id, triggers: [trigger]} =
        workflow = insert(:simple_workflow)

      insert(:workorder,
        workflow: workflow,
        trigger: trigger,
        dataclip: dataclip,
        state: :failed,
        inserted_at: Timex.shift(Timex.now(), months: -1)
      )

      assert %WorkflowStats{
               workflow: %{id: ^workflow_id},
               last_workorder: %{state: nil, updated_at: nil},
               last_failed_workorder: %{state: nil, updated_at: nil},
               runs_count: 0,
               runs_success_rate: 0.0,
               workorders_count: 0
             } = DashboardStats.get_workflow_stats(workflow)
    end

    test "returns a WorkflowStats with a failed last work order" do
      %{id: workflow_id} =
        workflow = complex_workflow_with_runs(last_workorder_failed: true)

      runs_success_rate =
        round(5 / 7 * 100 * 100) / 100

      assert %WorkflowStats{
               workflow: %{id: ^workflow_id},
               last_workorder: last_workorder,
               last_failed_workorder: last_workorder,
               failed_workorders_count: 1,
               grouped_attempts_count: grouped_attempts_count,
               grouped_workorders_count: grouped_workorders_count,
               runs_count: 8,
               runs_success_rate: ^runs_success_rate,
               workorders_count: 5
             } = DashboardStats.get_workflow_stats(workflow)

      assert %{
               failed: 1,
               pending: 2,
               running: 1,
               success: 1
             } = grouped_attempts_count

      assert %{
               failed: 1,
               pending: 1,
               running: 2,
               success: 1
             } = grouped_workorders_count
    end

    test "returns a WorkflowStats with a successful last work order" do
      %{id: workflow_id} =
        workflow = complex_workflow_with_runs(last_workorder_failed: false)

      runs_success_rate = round(5 / 7 * 100 * 100) / 100

      assert %WorkflowStats{
               workflow: %{id: ^workflow_id},
               last_workorder: last_workorder,
               last_failed_workorder: failed_last_workorder,
               failed_workorders_count: 1,
               grouped_attempts_count: grouped_attempts_count,
               grouped_workorders_count: grouped_workorders_count,
               runs_count: 8,
               runs_success_rate: ^runs_success_rate,
               workorders_count: 5
             } = DashboardStats.get_workflow_stats(workflow)

      assert last_workorder != failed_last_workorder
      assert last_workorder.state == :success

      assert %{
               failed: 1,
               pending: 2,
               running: 1,
               success: 1
             } = grouped_attempts_count

      assert %{
               failed: 1,
               pending: 1,
               running: 2,
               success: 1
             } = grouped_workorders_count
    end
  end

  describe "aggregate_project_metrics/1" do
    test "returns a valid ProjectMetrics" do
      workflow1 = complex_workflow_with_runs(last_workorder_failed: false)
      workflow2 = complex_workflow_with_runs(last_workorder_failed: true)

      workflow_stats1 = DashboardStats.get_workflow_stats(workflow1)
      workflow_stats2 = DashboardStats.get_workflow_stats(workflow2)

      success_percentage = round(2 * 100 * 100 / 4) / 100

      assert %ProjectMetrics{
               attempt_metrics: %{
                 failed: 2,
                 pending: 4,
                 success: 2,
                 success_percentage: ^success_percentage,
                 total: 10
               },
               work_order_metrics: %{
                 failed: 2,
                 pending: 2,
                 failed_percent: 20.0,
                 total: 10
               }
             } =
               DashboardStats.aggregate_project_metrics([
                 workflow_stats1,
                 workflow_stats2
               ])
    end
  end
end
