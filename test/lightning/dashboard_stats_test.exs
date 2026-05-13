defmodule Lightning.DashboardStatsTest do
  use Lightning.DataCase, async: true

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
        inserted_at: Timex.shift(Timex.now(), days: -30)
      )

      assert %WorkflowStats{
               workflow: %{id: ^workflow_id},
               last_workorder: %{state: nil, updated_at: nil},
               last_failed_workorder: %{state: nil, updated_at: nil},
               step_count: 0,
               step_success_rate: +0.0,
               workorders_count: 0
             } = DashboardStats.get_workflow_stats(workflow)
    end

    test "returns a WorkflowStats with a failed last work order" do
      %{id: workflow_id} =
        workflow = complex_workflow_with_runs(last_workorder_failed: true)

      step_success_rate =
        round(5 / 7 * 100 * 100) / 100

      assert %WorkflowStats{
               workflow: %{id: ^workflow_id},
               last_workorder: last_workorder,
               last_failed_workorder: last_workorder,
               failed_workorders_count: 1,
               grouped_runs_count: grouped_runs_count,
               grouped_workorders_count: grouped_workorders_count,
               step_count: 8,
               step_success_rate: ^step_success_rate,
               workorders_count: 5
             } = DashboardStats.get_workflow_stats(workflow)

      assert %{
               failed: 1,
               pending: 3,
               success: 1
             } = grouped_runs_count

      assert %{
               failed: 1,
               pending: 3,
               success: 1
             } = grouped_workorders_count
    end

    test "returns a WorkflowStats with a successful last work order" do
      %{id: workflow_id} =
        workflow = complex_workflow_with_runs(last_workorder_failed: false)

      step_success_rate = round(5 / 7 * 100 * 100) / 100

      assert %WorkflowStats{
               workflow: %{id: ^workflow_id},
               last_workorder: last_workorder,
               last_failed_workorder: failed_last_workorder,
               failed_workorders_count: 1,
               grouped_runs_count: grouped_runs_count,
               grouped_workorders_count: grouped_workorders_count,
               step_count: 8,
               step_success_rate: ^step_success_rate,
               workorders_count: 5
             } = DashboardStats.get_workflow_stats(workflow)

      assert last_workorder != failed_last_workorder
      assert last_workorder.state == :success

      assert %{
               failed: 1,
               pending: 3,
               success: 1
             } = grouped_runs_count

      assert %{
               failed: 1,
               pending: 3,
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

      success_rate = round(2 * 100 * 100 / 4) / 100
      failed_percent = round(2 * 100 * 100 / 10) / 100

      assert %ProjectMetrics{
               run_metrics: %{
                 failed: 2,
                 pending: 6,
                 success: 2,
                 success_rate: ^success_rate,
                 total: 10
               },
               work_order_metrics: %{
                 failed: 2,
                 pending: 6,
                 failed_percentage: ^failed_percent,
                 total: 10
               }
             } =
               DashboardStats.aggregate_project_metrics([
                 workflow_stats1,
                 workflow_stats2
               ])
    end
  end

  describe "sort_workflow_stats/3" do
    setup do
      w1 = complex_workflow_with_runs(last_workorder_failed: false)
      w2 = complex_workflow_with_runs(last_workorder_failed: true)
      w3 = complex_workflow_with_runs(last_workorder_failed: false)

      stats1 = %{
        DashboardStats.get_workflow_stats(w1)
        | workflow: %{name: "A Workflow"}
      }

      stats2 = %{
        DashboardStats.get_workflow_stats(w2)
        | workflow: %{name: "B Workflow"}
      }

      stats3 = %{
        DashboardStats.get_workflow_stats(w3)
        | workflow: %{name: "C Workflow"}
      }

      %{stats: [stats1, stats2, stats3]}
    end

    test "sorts by workorders_count ascending", %{stats: stats} do
      sorted =
        DashboardStats.sort_workflow_stats(stats, :workorders_count, :asc)

      counts = Enum.map(sorted, & &1.workorders_count)
      assert counts == Enum.sort(counts)
    end

    test "sorts by workorders_count descending", %{stats: stats} do
      sorted =
        DashboardStats.sort_workflow_stats(stats, :workorders_count, :desc)

      counts = Enum.map(sorted, & &1.workorders_count)
      assert counts == Enum.sort(counts, :desc)
    end

    test "sorts by failed_workorders_count ascending", %{stats: stats} do
      sorted =
        DashboardStats.sort_workflow_stats(
          stats,
          :failed_workorders_count,
          :asc
        )

      counts = Enum.map(sorted, & &1.failed_workorders_count)
      assert counts == Enum.sort(counts)
    end

    test "sorts by failed_workorders_count descending", %{stats: stats} do
      sorted =
        DashboardStats.sort_workflow_stats(
          stats,
          :failed_workorders_count,
          :desc
        )

      counts = Enum.map(sorted, & &1.failed_workorders_count)
      assert counts == Enum.sort(counts, :desc)
    end

    test "sorts by last_workorder_updated_at ascending", %{stats: stats} do
      sorted =
        DashboardStats.sort_workflow_stats(
          stats,
          :last_workorder_updated_at,
          :asc
        )

      timestamps = Enum.map(sorted, & &1.last_workorder.updated_at)
      assert timestamps == Enum.sort(timestamps, {:asc, DateTime})
    end

    test "sorts by last_workorder_updated_at descending", %{stats: stats} do
      sorted =
        DashboardStats.sort_workflow_stats(
          stats,
          :last_workorder_updated_at,
          :desc
        )

      timestamps = Enum.map(sorted, & &1.last_workorder.updated_at)
      assert timestamps == Enum.sort(timestamps, {:desc, DateTime})
    end

    test "sorts by last_workorder_updated_at chronologically across a UTC month boundary",
         %{stats: [stats1, stats2, stats3]} do
      later = ~U[2026-05-01 01:10:00.000000Z]
      earlier = ~U[2026-04-30 23:10:00.000000Z]
      earliest = ~U[2026-04-30 21:10:00.000000Z]

      stats1 = put_in(stats1.last_workorder.updated_at, later)
      stats2 = put_in(stats2.last_workorder.updated_at, earlier)
      stats3 = put_in(stats3.last_workorder.updated_at, earliest)

      sorted_desc =
        DashboardStats.sort_workflow_stats(
          [stats2, stats3, stats1],
          :last_workorder_updated_at,
          :desc
        )

      assert Enum.map(sorted_desc, & &1.last_workorder.updated_at) ==
               [later, earlier, earliest]

      sorted_asc =
        DashboardStats.sort_workflow_stats(
          [stats1, stats2, stats3],
          :last_workorder_updated_at,
          :asc
        )

      assert Enum.map(sorted_asc, & &1.last_workorder.updated_at) ==
               [earliest, earlier, later]
    end

    test "sorts by workflow name when given invalid sort field", %{stats: stats} do
      sorted = DashboardStats.sort_workflow_stats(stats, :invalid_field, :asc)
      names = Enum.map(sorted, & &1.workflow.name)
      assert names == ["A Workflow", "B Workflow", "C Workflow"]
    end

    test "handles nil last_workorder_updated_at when sorting by timestamp", %{
      stats: [stats1 | rest]
    } do
      stats_with_nil = put_in(stats1.last_workorder.updated_at, nil)
      all_stats = [stats_with_nil | rest]

      sorted =
        DashboardStats.sort_workflow_stats(
          all_stats,
          :last_workorder_updated_at,
          :asc
        )

      first_stat = List.first(sorted)

      assert first_stat.last_workorder.updated_at == nil
    end

    test "keeps nil and a real 1970-01-01 timestamp cleanly separated", %{
      stats: [stats1, stats2 | _]
    } do
      # The sort-key extractor returns a sentinel tuple ({0, _} for nil,
      # {1, _} for present) so nil rows can never tie with a real
      # `~U[1970-01-01 00:00:00Z]` row even though both map to unix 0.
      stats_nil = put_in(stats1.last_workorder.updated_at, nil)

      stats_epoch =
        put_in(stats2.last_workorder.updated_at, ~U[1970-01-01 00:00:00Z])

      asc =
        DashboardStats.sort_workflow_stats(
          [stats_epoch, stats_nil],
          :last_workorder_updated_at,
          :asc
        )

      assert Enum.map(asc, & &1.last_workorder.updated_at) ==
               [nil, ~U[1970-01-01 00:00:00Z]]

      desc =
        DashboardStats.sort_workflow_stats(
          [stats_nil, stats_epoch],
          :last_workorder_updated_at,
          :desc
        )

      assert Enum.map(desc, & &1.last_workorder.updated_at) ==
               [~U[1970-01-01 00:00:00Z], nil]
    end
  end
end
