defmodule Lightning.DashboardStatsTest do
  @moduledoc false
  use Lightning.DataCase

  import Lightning.Factories

  alias Lightning.DashboardStats
  alias Lightning.DashboardStats.WorkflowStats
  alias Lightning.DashboardStats.ProjectMetrics

  def setup_last_workorder_failed() do
    project = insert(:project)

    %{jobs: [job0, job1, job2, job3, job4, job5, job6]} =
      workflow = insert(:complex_workflow, project: project)

    trigger = insert(:trigger, workflow: workflow)

    insert(:workorder,
      workflow: workflow,
      trigger: trigger,
      dataclip: build(:dataclip),
      state: :pending
    )

    insert(:workorder,
      workflow: workflow,
      trigger: trigger,
      dataclip: build(:dataclip),
      state: :success,
      attempts: [
        %{
          state: :success,
          dataclip: build(:dataclip),
          starting_trigger: trigger,
          runs:
            Enum.map([job0, job4, job5, job6], fn job ->
              # job6 run started but not completed
              exit_reason = if job == job6, do: nil, else: "success"
              insert(:run, job: job, exit_reason: exit_reason)
            end)
        }
      ]
    )

    insert(:workorder,
      workflow: workflow,
      trigger: trigger,
      dataclip: build(:dataclip),
      state: :running
    )

    insert(:workorder,
      workflow: workflow,
      trigger: trigger,
      dataclip: build(:dataclip),
      state: :failed,
      attempts: [
        %{
          state: :failed,
          dataclip: build(:dataclip),
          starting_trigger: trigger,
          runs:
            Enum.map([job0, job1, job2, job3], fn job ->
              exit_reason =
                if job == job0 || job == job3, do: "fail", else: "success"

              insert(:run, job: job, exit_reason: exit_reason)
            end)
        }
      ]
    )

    workflow
  end

  def setup_last_workorder_succeeded() do
    project = insert(:project)

    %{jobs: [job0, job1, job2, job3, job4, job5, job6]} =
      workflow = insert(:complex_workflow, project: project)

    trigger = insert(:trigger, workflow: workflow)

    insert(:workorder,
      workflow: workflow,
      trigger: trigger,
      dataclip: build(:dataclip),
      state: :pending
    )

    insert(:workorder,
      workflow: workflow,
      trigger: trigger,
      dataclip: build(:dataclip),
      state: :running
    )

    insert(:workorder,
      workflow: workflow,
      trigger: trigger,
      dataclip: build(:dataclip),
      state: :failed,
      attempts: [
        %{
          state: :failed,
          dataclip: build(:dataclip),
          starting_trigger: trigger,
          runs:
            Enum.map([job0, job1, job2, job3], fn job ->
              exit_reason =
                if job == job0 || job == job3, do: "fail", else: "success"

              insert(:run, job: job, exit_reason: exit_reason)
            end)
        }
      ]
    )

    insert(:workorder,
      workflow: workflow,
      trigger: trigger,
      dataclip: build(:dataclip),
      state: :success,
      attempts: [
        %{
          state: :success,
          dataclip: build(:dataclip),
          starting_trigger: trigger,
          runs:
            Enum.map([job0, job4, job5, job6], fn job ->
              # job6 run started but not completed
              exit_reason = if job == job6, do: nil, else: "success"
              insert(:run, job: job, exit_reason: exit_reason)
            end)
        }
      ]
    )

    workflow
  end

  describe "get_workflow_stats/1" do
    test "returns a WorkflowStats with a failed last work order" do
      %{id: workflow_id} = workflow = setup_last_workorder_failed()

      runs_success_percentage = 5 / 8 * 100

      assert %WorkflowStats{
               workflow: %{id: ^workflow_id},
               last_workorder: last_workorder,
               last_failed_workorder: last_workorder,
               failed_workorders_count: 1,
               grouped_runs_count: grouped_runs_count,
               grouped_workorders_count: grouped_workorders_count,
               runs_count: 8,
               runs_success_percentage: ^runs_success_percentage,
               workorders_count: 4
             } = DashboardStats.get_workflow_stats(workflow)

      assert %{
               failed: 2,
               pending: 1,
               success: 5
             } = grouped_runs_count

      assert %{
               failed: 1,
               unfinished: 2,
               success: 1
             } = grouped_workorders_count
    end

    test "returns a WorkflowStats with a successful last work order" do
      %{id: workflow_id} = workflow = setup_last_workorder_succeeded()

      runs_success_percentage = 5 / 8 * 100

      assert %WorkflowStats{
               workflow: %{id: ^workflow_id},
               last_workorder: last_workorder,
               last_failed_workorder: failed_last_workorder,
               failed_workorders_count: 1,
               grouped_runs_count: grouped_runs_count,
               grouped_workorders_count: grouped_workorders_count,
               runs_count: 8,
               runs_success_percentage: ^runs_success_percentage,
               workorders_count: 4
             } = DashboardStats.get_workflow_stats(workflow)

      assert last_workorder != failed_last_workorder
      assert last_workorder.state == :success

      assert %{
               failed: 2,
               pending: 1,
               success: 5
             } = grouped_runs_count

      assert %{
               failed: 1,
               unfinished: 2,
               success: 1
             } = grouped_workorders_count
    end
  end

  describe "aggregate_project_metrics/1" do
    test "returns a valid ProjectMetrics" do
      workflow1 = setup_last_workorder_succeeded()
      workflow2 = setup_last_workorder_failed()

      workflow_stats1 = DashboardStats.get_workflow_stats(workflow1)
      workflow_stats2 = DashboardStats.get_workflow_stats(workflow2)

      success_percentage = round(10 / 14 * 100 * 100) / 100

      assert %ProjectMetrics{
               run_metrics: %{
                 completed: 14,
                 pending: 2,
                 success: 10,
                 success_percentage: ^success_percentage,
                 total: 16,
                 failed: 4
               },
               work_order_metrics: %{
                 failed: 2,
                 failure_percentage: 25.0,
                 total: 8
               }
             } =
               DashboardStats.aggregate_project_metrics([
                 workflow_stats1,
                 workflow_stats2
               ])
    end
  end
end
