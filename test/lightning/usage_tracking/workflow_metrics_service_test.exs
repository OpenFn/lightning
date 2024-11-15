defmodule Lightning.UsageTracking.WorkflowMetricsServiceTest do
  use Lightning.DataCase, async: true

  alias Lightning.UsageTracking.WorkflowMetricsService

  @date ~D[2024-02-05]
  @finished_at ~U[2024-02-05 12:11:10Z]
  @hashed_id "EECF8CFDD120E8DF8D9A12CA92AC3E815908223F95CFB11F19261A3C0EB34AEC"
  @workflow_id "3cfb674b-e878-470d-b7c0-cfa8f7e003ae"

  describe "generate_metrics/3" do
    setup do
      no_of_jobs = 6
      no_of_work_orders = 3
      no_of_runs_per_work_order = 2
      no_of_unique_jobs_in_steps = 2
      no_of_steps_per_unique_job = 4

      workflow =
        build_workflow(
          @workflow_id,
          no_of_jobs: no_of_jobs,
          no_of_work_orders: no_of_work_orders,
          no_of_runs_per_work_order: no_of_runs_per_work_order,
          no_of_unique_jobs_in_steps: no_of_unique_jobs_in_steps,
          no_of_steps_per_unique_job: no_of_steps_per_unique_job
        )

      _other_workflow =
        build_workflow(
          Ecto.UUID.generate(),
          no_of_jobs: no_of_jobs + 1,
          no_of_work_orders: no_of_work_orders + 1,
          no_of_runs_per_work_order: no_of_runs_per_work_order + 1,
          no_of_unique_jobs_in_steps: no_of_unique_jobs_in_steps + 1,
          no_of_steps_per_unique_job: no_of_steps_per_unique_job + 1
        )

      no_of_runs = no_of_work_orders * no_of_runs_per_work_order

      no_of_steps =
        no_of_runs * no_of_unique_jobs_in_steps * no_of_steps_per_unique_job

      %{
        workflow: workflow,
        no_of_jobs: no_of_jobs,
        no_of_runs: no_of_runs,
        no_of_steps: no_of_steps,
        no_of_unique_jobs: no_of_unique_jobs_in_steps
      }
    end

    test "returns the appropriate metrics depending on cleartext_uuids are enable or not",
         %{
           no_of_jobs: no_of_jobs,
           no_of_runs: no_of_runs,
           no_of_steps: no_of_steps,
           no_of_unique_jobs: no_of_unique_jobs,
           workflow: workflow
         } do
      Mox.expect(Lightning.MockConfig, :usage_tracking_run_chunk_size, 2, fn ->
        100
      end)

      assert %{
               hashed_uuid: @hashed_id,
               cleartext_uuid: nil,
               no_of_active_jobs: no_of_unique_jobs,
               no_of_jobs: no_of_jobs,
               no_of_runs: no_of_runs,
               no_of_steps: no_of_steps
             } ==
               WorkflowMetricsService.generate_metrics(workflow, false, @date)

      assert %{
               hashed_uuid: @hashed_id,
               cleartext_uuid: @workflow_id,
               no_of_active_jobs: no_of_unique_jobs,
               no_of_jobs: no_of_jobs,
               no_of_runs: no_of_runs,
               no_of_steps: no_of_steps
             } ==
               WorkflowMetricsService.generate_metrics(workflow, true, @date)

      Mox.verify!()
    end
  end

  describe ".filter_eligible_workflows" do
    test "returns workflows that existed on or before the date" do
      date = ~D[2024-02-05]

      eligible_workflow_1 =
        insert(
          :workflow,
          name: "e-1",
          inserted_at: ~U[2024-02-04 12:00:00Z],
          deleted_at: nil
        )

      eligible_workflow_2 =
        insert(
          :workflow,
          name: "e-2",
          inserted_at: ~U[2024-02-05 23:59:59Z],
          deleted_at: nil
        )

      eligible_workflow_3 =
        insert(
          :workflow,
          name: "e-3",
          inserted_at: ~U[2024-02-04 12:00:00Z],
          deleted_at: ~U[2024-02-06 00:00:00Z]
        )

      eligible_workflow_4 =
        insert(
          :workflow,
          name: "e-4",
          inserted_at: ~U[2024-02-04 12:00:00Z],
          deleted_at: ~U[2024-02-06 00:00:01Z]
        )

      ineligible_workflow_deleted_before_1 =
        insert(
          :workflow,
          name: "ib-1",
          inserted_at: ~U[2024-02-04 12:00:00Z],
          deleted_at: ~U[2024-02-05 23:59:59Z]
        )

      ineligible_workflow_deleted_before_2 =
        insert(
          :workflow,
          name: "ib-2",
          inserted_at: ~U[2024-02-04 12:00:00Z],
          deleted_at: ~U[2024-02-05 23:59:58Z]
        )

      ineligible_workflow_created_after_1 =
        insert(
          :workflow,
          name: "ca-1",
          inserted_at: ~U[2024-02-06 00:00:00Z],
          deleted_at: nil
        )

      ineligible_workflow_created_after_2 =
        insert(
          :workflow,
          name: "ca-2",
          inserted_at: ~U[2024-02-06 00:00:01Z],
          deleted_at: ~U[2024-02-06 00:00:02Z]
        )

      all_workflows = [
        eligible_workflow_1,
        ineligible_workflow_deleted_before_1,
        ineligible_workflow_created_after_1,
        eligible_workflow_2,
        ineligible_workflow_deleted_before_2,
        eligible_workflow_3,
        ineligible_workflow_created_after_2,
        eligible_workflow_4
      ]

      expected_workflows = [
        eligible_workflow_1,
        eligible_workflow_2,
        eligible_workflow_3,
        eligible_workflow_4
      ]

      workflows =
        WorkflowMetricsService.find_eligible_workflows(all_workflows, date)

      assert workflows == expected_workflows
    end
  end

  defp build_workflow(workflow_id, opts) do
    no_of_jobs = opts |> Keyword.get(:no_of_jobs)
    no_of_work_orders = opts |> Keyword.get(:no_of_work_orders)
    no_of_runs_per_work_order = opts |> Keyword.get(:no_of_runs_per_work_order)
    no_of_unique_jobs_in_steps = opts |> Keyword.get(:no_of_unique_jobs_in_steps)
    no_of_steps_per_unique_job = opts |> Keyword.get(:no_of_steps_per_unique_job)

    workflow = insert(:workflow, id: workflow_id)

    jobs =
      no_of_jobs
      |> insert_list(:job, workflow: workflow)
      |> Enum.take(no_of_unique_jobs_in_steps)

    work_orders = insert_list(no_of_work_orders, :workorder, workflow: workflow)

    for work_order <- work_orders do
      insert_runs_with_steps(
        no_of_runs_per_work_order: no_of_runs_per_work_order,
        no_of_steps_per_unique_job: no_of_steps_per_unique_job,
        work_order: work_order,
        jobs: jobs
      )
    end

    workflow |> Repo.preload([:jobs, runs: [steps: [:job]]])
  end

  defp insert_runs_with_steps(opts) do
    no_of_runs_per_work_order = opts |> Keyword.get(:no_of_runs_per_work_order)
    no_of_steps_per_unique_job = opts |> Keyword.get(:no_of_steps_per_unique_job)
    work_order = opts |> Keyword.get(:work_order)
    jobs = opts |> Keyword.get(:jobs)

    [starting_job | _] = jobs

    insert_list(
      no_of_runs_per_work_order,
      :run,
      work_order: work_order,
      dataclip: &dataclip_builder/0,
      finished_at: @finished_at,
      state: :success,
      starting_job: starting_job,
      steps: fn -> build_steps(jobs, no_of_steps_per_unique_job) end
    )
  end

  defp build_steps(jobs, no_of_steps_per_unique_job) do
    jobs
    |> Enum.flat_map(fn job ->
      build_list(
        no_of_steps_per_unique_job,
        :step,
        input_dataclip: &dataclip_builder/0,
        output_dataclip: &dataclip_builder/0,
        job: job,
        finished_at: @finished_at
      )
    end)
  end

  defp dataclip_builder, do: build(:dataclip)
end
