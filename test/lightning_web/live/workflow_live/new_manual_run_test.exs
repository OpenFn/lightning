defmodule LightningWeb.WorkflowLive.NewManualRunTest do
  use LightningWeb.ConnCase
  import Lightning.Factories

  alias LightningWeb.WorkflowLive.NewManualRun

  test "get_dataclips_filters/1" do
    assert {:ok, %{}} = NewManualRun.get_dataclips_filters("query=+")

    assert {:ok, %{before: ~N[2025-05-14 14:35:00]}} =
             NewManualRun.get_dataclips_filters(
               "query=+&before=2025-05-14T14%3A35"
             )

    assert {:ok,
            %{before: ~N[2025-05-14 14:35:00], after: ~N[2025-05-14 14:55:00]}} =
             NewManualRun.get_dataclips_filters(
               "query=+&before=2025-05-14T14%3A35&after=2025-05-14T14%3A55"
             )

    assert {:ok, %{name_or_id_part: "1f"}} =
             NewManualRun.get_dataclips_filters("query=1f")

    uuid = "3a80bd03-6f0b-4146-8b23-e5ca9f3176bb"

    assert {:ok, %{id: ^uuid}} =
             NewManualRun.get_dataclips_filters("query=#{uuid}")

    assert {:ok, %{name_or_id_part: "abc"}} =
             NewManualRun.get_dataclips_filters("query=abc")

    assert {:ok, %{name_part: "long"}} =
             NewManualRun.get_dataclips_filters("query=long")

    invalid_uuid = "123#{uuid}z"

    assert {:ok, %{name_part: ^invalid_uuid}} =
             NewManualRun.get_dataclips_filters("query=#{invalid_uuid}"),
           "Invalid uuids are treated as name prefixes"

    for type <- Lightning.Invocation.Dataclip.source_types() do
      assert {:ok, %{type: ^type}} =
               NewManualRun.get_dataclips_filters("query=+&type=#{type}"),
             "should allow a type of #{type}"
    end

    assert {:error, changeset} =
             NewManualRun.get_dataclips_filters("query=+&type=invalid_type")

    assert changeset.errors |> Enum.any?(&match?({:type, {"is invalid", _}}, &1))
  end

  describe "search_selectable_dataclips/4" do
    test "returns next cron run for cron-triggered workflows with successful runs" do
      project = insert(:project)

      # Create a cron-triggered workflow
      cron_trigger = build(:trigger, type: :cron, cron_expression: "0 0 * * *")
      job = build(:job)

      workflow =
        build(:workflow, project: project)
        |> with_trigger(cron_trigger)
        |> with_job(job)
        |> with_edge({cron_trigger, job})
        |> insert()
        |> with_snapshot()

      # Create a successful step with output dataclip
      input_dataclip =
        insert(:dataclip, project: project, body: %{"input" => "data"})

      output_dataclip =
        insert(:dataclip,
          project: project,
          body: %{"output" => "result"},
          type: :step_result
        )

      insert(:step,
        job: workflow.jobs |> List.first(),
        input_dataclip: input_dataclip,
        output_dataclip: output_dataclip,
        exit_reason: "success",
        finished_at: DateTime.utc_now()
      )

      job_id = workflow.jobs |> List.first() |> Map.get(:id)

      {:ok, result} =
        NewManualRun.search_selectable_dataclips(job_id, "query=+", 10, 0)

      assert %{
               dataclips: dataclips,
               next_cron_run_dataclip_id: next_cron_run_dataclip_id
             } = result

      assert next_cron_run_dataclip_id == output_dataclip.id
      assert List.first(dataclips).id == output_dataclip.id
    end

    test "returns next cron run for cron-triggered workflows with successful runs that matches name" do
      project = insert(:project)

      # Create a cron-triggered workflow
      cron_trigger = build(:trigger, type: :cron, cron_expression: "0 0 * * *")
      job = build(:job)

      workflow =
        build(:workflow, project: project)
        |> with_trigger(cron_trigger)
        |> with_job(job)
        |> with_edge({cron_trigger, job})
        |> insert()
        |> with_snapshot()

      # Create a successful step with output dataclip
      input_dataclip =
        insert(:dataclip, project: project, body: %{"input" => "data"})

      output_dataclip =
        insert(:dataclip,
          name: "123abc246",
          project: project,
          body: %{"output" => "result"},
          type: :step_result
        )

      insert(:step,
        job: workflow.jobs |> List.first(),
        input_dataclip: input_dataclip,
        output_dataclip: output_dataclip,
        exit_reason: "success",
        finished_at: DateTime.utc_now()
      )

      job_id = workflow.jobs |> List.first() |> Map.get(:id)

      {:ok, result} =
        NewManualRun.search_selectable_dataclips(job_id, "query=abc", 10, 0)

      assert %{
               dataclips: dataclips,
               next_cron_run_dataclip_id: next_cron_run_dataclip_id
             } = result

      assert next_cron_run_dataclip_id == output_dataclip.id
      assert List.first(dataclips).id == output_dataclip.id
    end

    test "does not return next cron run for cron-triggered that don't match the name" do
      project = insert(:project)

      # Create a cron-triggered workflow
      cron_trigger = build(:trigger, type: :cron, cron_expression: "0 0 * * *")
      job = build(:job)

      workflow =
        build(:workflow, project: project)
        |> with_trigger(cron_trigger)
        |> with_job(job)
        |> with_edge({cron_trigger, job})
        |> insert()
        |> with_snapshot()

      # Create a successful step with output dataclip
      input_dataclip =
        insert(:dataclip, project: project, body: %{"input" => "data"})

      output_dataclip =
        insert(:dataclip,
          project: project,
          body: %{"output" => "result"},
          type: :step_result
        )

      insert(:step,
        job: hd(workflow.jobs),
        input_dataclip: input_dataclip,
        output_dataclip: output_dataclip,
        exit_reason: "success",
        finished_at: DateTime.utc_now()
      )

      job_id = workflow.jobs |> hd() |> Map.get(:id)

      {:ok, result} =
        NewManualRun.search_selectable_dataclips(job_id, "query=abc", 10, 0)

      assert %{
               dataclips: [],
               next_cron_run_dataclip_id: next_cron_run_dataclip_id
             } = result

      assert next_cron_run_dataclip_id == output_dataclip.id
    end

    test "does not return next cron run for webhook-triggered workflows" do
      project = insert(:project)

      # Create a webhook-triggered workflow
      webhook_trigger = build(:trigger, type: :webhook)
      job = build(:job)

      workflow =
        build(:workflow, project: project)
        |> with_trigger(webhook_trigger)
        |> with_job(job)
        |> with_edge({webhook_trigger, job})
        |> insert()
        |> with_snapshot()

      # Create a successful step with output dataclip
      input_dataclip =
        insert(:dataclip, project: project, body: %{"input" => "data"})

      output_dataclip =
        insert(:dataclip,
          project: project,
          body: %{"output" => "result"},
          type: :step_result
        )

      insert(:step,
        job: workflow.jobs |> List.first(),
        input_dataclip: input_dataclip,
        output_dataclip: output_dataclip,
        exit_reason: "success",
        finished_at: DateTime.utc_now()
      )

      job_id = workflow.jobs |> List.first() |> Map.get(:id)

      {:ok, result} =
        NewManualRun.search_selectable_dataclips(job_id, "query=+", 10, 0)

      assert %{
               dataclips: _dataclips,
               next_cron_run_dataclip_id: next_cron_run_dataclip_id
             } =
               result

      assert next_cron_run_dataclip_id == nil
    end

    test "does not return next cron run for cron-triggered workflows with no runs" do
      project = insert(:project)

      # Create a cron-triggered workflow without any runs
      cron_trigger = build(:trigger, type: :cron, cron_expression: "0 0 * * *")
      job = build(:job)

      workflow =
        build(:workflow, project: project)
        |> with_trigger(cron_trigger)
        |> with_job(job)
        |> with_edge({cron_trigger, job})
        |> insert()
        |> with_snapshot()

      job_id = workflow.jobs |> List.first() |> Map.get(:id)

      {:ok, result} =
        NewManualRun.search_selectable_dataclips(job_id, "query=+", 10, 0)

      assert %{
               dataclips: _dataclips,
               next_cron_run_dataclip_id: next_cron_run_dataclip_id
             } =
               result

      assert next_cron_run_dataclip_id == nil
    end

    test "does not return next cron run for cron-triggered workflows with only failed runs" do
      project = insert(:project)

      # Create a cron-triggered workflow
      cron_trigger = build(:trigger, type: :cron, cron_expression: "0 0 * * *")
      job = build(:job)

      workflow =
        build(:workflow, project: project)
        |> with_trigger(cron_trigger)
        |> with_job(job)
        |> with_edge({cron_trigger, job})
        |> insert()
        |> with_snapshot()

      # Create a failed step (no output dataclip for failed steps)
      input_dataclip =
        insert(:dataclip, project: project, body: %{"input" => "data"})

      insert(:step,
        job: workflow.jobs |> List.first(),
        input_dataclip: input_dataclip,
        output_dataclip: nil,
        exit_reason: "failed",
        finished_at: DateTime.utc_now()
      )

      job_id = workflow.jobs |> List.first() |> Map.get(:id)

      {:ok, result} =
        NewManualRun.search_selectable_dataclips(job_id, "query=+", 10, 0)

      assert %{
               dataclips: _dataclips,
               next_cron_run_dataclip_id: next_cron_run_dataclip_id
             } =
               result

      assert next_cron_run_dataclip_id == nil
    end

    test "does not return next cron run for cron-triggered workflows with failed runs after successful ones" do
      project = insert(:project)

      # Create a cron-triggered workflow
      cron_trigger = build(:trigger, type: :cron, cron_expression: "0 0 * * *")
      job = build(:job)

      workflow =
        build(:workflow, project: project)
        |> with_trigger(cron_trigger)
        |> with_job(job)
        |> with_edge({cron_trigger, job})
        |> insert()
        |> with_snapshot()

      # Create a successful step with output dataclip (older)
      input_dataclip1 =
        insert(:dataclip, project: project, body: %{"input" => "data1"})

      output_dataclip1 =
        insert(:dataclip,
          project: project,
          body: %{"output" => "result1"},
          type: :step_result
        )

      insert(:step,
        job: workflow.jobs |> List.first(),
        input_dataclip: input_dataclip1,
        output_dataclip: output_dataclip1,
        exit_reason: "success",
        # 1 hour ago
        finished_at: DateTime.utc_now() |> DateTime.add(-3600, :second)
      )

      # Create a failed step (more recent)
      input_dataclip2 =
        insert(:dataclip, project: project, body: %{"input" => "data2"})

      insert(:step,
        job: workflow.jobs |> List.first(),
        input_dataclip: input_dataclip2,
        output_dataclip: nil,
        exit_reason: "failed",
        finished_at: DateTime.utc_now()
      )

      job_id = workflow.jobs |> List.first() |> Map.get(:id)

      {:ok, result} =
        NewManualRun.search_selectable_dataclips(job_id, "query=+", 10, 0)

      # Should still return the successful run's output as next cron run
      # because last_successful_step_for_job looks for the most recent successful step
      assert %{
               dataclips: dataclips,
               next_cron_run_dataclip_id: next_cron_run_dataclip_id
             } = result

      assert next_cron_run_dataclip_id == output_dataclip1.id
      assert List.first(dataclips).id == output_dataclip1.id
    end
  end
end
