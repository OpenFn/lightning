defmodule Lightning.UsageTracking.WorkflowMetricsQueryTest do
  use Lightning.DataCase, async: true

  alias Lightning.Repo
  alias Lightning.Run
  alias Lightning.UsageTracking.WorkflowMetricsQuery

  describe "workflow_runs" do
    setup do
      workflow = insert(:workflow)
      other_workflow = insert(:workflow)

      work_order_1 = insert(:workorder, workflow: workflow)
      work_order_2 = insert(:workorder, workflow: workflow)

      other_work_order = insert(:workorder, workflow: other_workflow)

      run_1 =
        insert(
          :run,
          work_order: work_order_1,
          dataclip: build(:dataclip),
          starting_job: build(:job)
        )

      run_2 =
        insert(
          :run,
          work_order: work_order_2,
          dataclip: build(:dataclip),
          starting_job: build(:job)
        )

      _other_run =
        insert(
          :run,
          work_order: other_work_order,
          dataclip: build(:dataclip),
          starting_job: build(:job)
        )

      %{
        run_1: run_1,
        run_2: run_2,
        workflow: workflow
      }
    end

    test "returns all runs linked to the given workflow", %{
      run_1: %{id: run_1_id},
      run_2: %{id: run_2_id},
      workflow: workflow
    } do
      runs = WorkflowMetricsQuery.workflow_runs(workflow) |> Repo.all()

      expected_ids = [run_1_id, run_2_id] |> Enum.sort()

      actual_ids = runs |> Enum.map(fn %Run{id: id} -> id end) |> Enum.sort()

      assert actual_ids == expected_ids
    end
  end

  describe "runs_finished_on" do
    setup do
      work_order = insert(:workorder, workflow: build(:workflow))

      date = ~D[2024-11-13]
      inclusive_start_time = DateTime.new!(date, ~T[00:00:00])
      exclusive_end_time = DateTime.new!(Date.add(date, 1), ~T[00:00:00])

      _null_finished_at_run =
        insert(
          :run,
          work_order: work_order,
          dataclip: build(:dataclip),
          starting_job: build(:job)
        )

      _too_early_run =
        insert(
          :run,
          work_order: work_order,
          dataclip: build(:dataclip),
          starting_job: build(:job),
          finished_at: DateTime.add(inclusive_start_time, -1, :second)
        )

      run_1 =
        insert(
          :run,
          work_order: work_order,
          dataclip: build(:dataclip),
          starting_job: build(:job),
          finished_at: inclusive_start_time
        )

      run_2 =
        insert(
          :run,
          work_order: work_order,
          dataclip: build(:dataclip),
          starting_job: build(:job),
          finished_at: DateTime.add(exclusive_end_time, -1, :second)
        )

      _too_late_run =
        insert(
          :run,
          work_order: work_order,
          dataclip: build(:dataclip),
          starting_job: build(:job),
          finished_at: exclusive_end_time
        )

      %{
        date: date,
        run_1: run_1,
        run_2: run_2
      }
    end

    test "returns all runs that finished on the given date", %{
      date: date,
      run_1: %{id: run_1_id},
      run_2: %{id: run_2_id}
    } do
      base_query = from(r in Run)

      runs =
        base_query
        |> WorkflowMetricsQuery.runs_finished_on(date)
        |> Repo.all()

      expected_ids = [run_1_id, run_2_id] |> Enum.sort()

      actual_ids = runs |> Enum.map(fn %Run{id: id} -> id end) |> Enum.sort()

      assert actual_ids == expected_ids
    end
  end
end
