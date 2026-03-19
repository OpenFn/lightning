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

  describe "cron cursor: next cron run dataclip" do
    defp build_two_job_cron_workflow(project, opts \\ []) do
      cron_trigger = build(:trigger, type: :cron, cron_expression: "0 0 * * *")
      job_a = build(:job, name: "Job A")
      job_b = build(:job, name: "Job B")

      workflow =
        build(:workflow, project: project)
        |> with_trigger(cron_trigger)
        |> with_job(job_a)
        |> with_job(job_b)
        |> with_edge({cron_trigger, job_a})
        |> with_edge({job_a, job_b})
        |> insert()
        |> with_snapshot()

      job_a_record = Enum.find(workflow.jobs, &(&1.name == "Job A"))
      job_b_record = Enum.find(workflow.jobs, &(&1.name == "Job B"))
      trigger_record = hd(workflow.triggers)

      if cursor_job_id = opts[:cron_cursor_job_id] do
        trigger_record
        |> Ecto.Changeset.change(%{cron_cursor_job_id: cursor_job_id})
        |> Lightning.Repo.update!()
      end

      %{
        workflow: workflow,
        trigger: trigger_record,
        job_a: job_a_record,
        job_b: job_b_record
      }
    end

    defp create_successful_run(workflow, trigger, project, final_dataclip) do
      snapshot = Lightning.Workflows.Snapshot.get_current_for(workflow)

      work_order =
        insert(:workorder,
          workflow: workflow,
          trigger_id: trigger.id,
          snapshot: snapshot
        )
        |> with_run(
          build(:run,
            dataclip:
              insert(:dataclip, project: project, body: %{"init" => true}),
            snapshot: snapshot,
            starting_trigger: trigger
          )
        )

      run = hd(work_order.runs)

      run
      |> Ecto.Changeset.change(%{state: :claimed})
      |> Lightning.Repo.update!()

      run
      |> Ecto.Changeset.change(%{
        state: :success,
        finished_at: DateTime.utc_now(),
        final_dataclip_id: final_dataclip.id
      })
      |> Lightning.Repo.update!()
    end

    test "cursor nil: uses final_dataclip_id from the last successful run, not step outputs" do
      project = insert(:project)

      %{workflow: workflow, trigger: trigger, job_a: job_a, job_b: job_b} =
        build_two_job_cron_workflow(project)

      # The run's final_dataclip -- this is what the cron scheduler should pick
      final_dataclip =
        insert(:dataclip,
          project: project,
          body: %{"final" => "run state"},
          type: :step_result
        )

      create_successful_run(workflow, trigger, project, final_dataclip)

      # Create step outputs for both jobs -- these should NOT be chosen
      job_a_output =
        insert(:dataclip,
          project: project,
          body: %{"job_a" => "output"},
          type: :step_result
        )

      job_b_output =
        insert(:dataclip,
          project: project,
          body: %{"job_b" => "output"},
          type: :step_result
        )

      insert(:step,
        job: job_a,
        input_dataclip: insert(:dataclip, project: project, body: %{}),
        output_dataclip: job_a_output,
        exit_reason: "success",
        finished_at: DateTime.utc_now()
      )

      insert(:step,
        job: job_b,
        input_dataclip: insert(:dataclip, project: project, body: %{}),
        output_dataclip: job_b_output,
        exit_reason: "success",
        finished_at: DateTime.utc_now()
      )

      {:ok, result} =
        NewManualRun.search_selectable_dataclips(
          job_a.id,
          "query=+",
          10,
          0
        )

      # Must be the run's final_dataclip, not any step output
      assert result.next_cron_run_dataclip_id == final_dataclip.id
      refute result.next_cron_run_dataclip_id == job_a_output.id
      refute result.next_cron_run_dataclip_id == job_b_output.id
    end

    test "cursor set to job_b: uses job_b's step output, not job_a's or the run's final_dataclip" do
      project = insert(:project)

      %{workflow: workflow, trigger: trigger, job_a: job_a, job_b: job_b} =
        build_two_job_cron_workflow(project,
          cron_cursor_job_id: nil
        )

      # We need the job_b id, so update the trigger now
      trigger
      |> Ecto.Changeset.change(%{cron_cursor_job_id: job_b.id})
      |> Lightning.Repo.update!()

      # Create a run with a final_dataclip that should NOT be chosen
      final_dataclip =
        insert(:dataclip,
          project: project,
          body: %{"final" => "run state"},
          type: :step_result
        )

      create_successful_run(workflow, trigger, project, final_dataclip)

      # Step outputs: different dataclips for each job
      job_a_output =
        insert(:dataclip,
          project: project,
          body: %{"job_a" => "output"},
          type: :step_result
        )

      job_b_output =
        insert(:dataclip,
          project: project,
          body: %{"job_b" => "output"},
          type: :step_result
        )

      insert(:step,
        job: job_a,
        input_dataclip: insert(:dataclip, project: project, body: %{}),
        output_dataclip: job_a_output,
        exit_reason: "success",
        finished_at: DateTime.utc_now()
      )

      insert(:step,
        job: job_b,
        input_dataclip: insert(:dataclip, project: project, body: %{}),
        output_dataclip: job_b_output,
        exit_reason: "success",
        finished_at: DateTime.utc_now()
      )

      {:ok, result} =
        NewManualRun.search_selectable_dataclips(
          job_a.id,
          "query=+",
          10,
          0
        )

      # Must be job_b's step output specifically
      assert result.next_cron_run_dataclip_id == job_b_output.id
      refute result.next_cron_run_dataclip_id == job_a_output.id
      refute result.next_cron_run_dataclip_id == final_dataclip.id
    end

    test "cursor nil, no successful runs: returns nil" do
      project = insert(:project)

      %{job_a: job_a} = build_two_job_cron_workflow(project)

      {:ok, result} =
        NewManualRun.search_selectable_dataclips(
          job_a.id,
          "query=+",
          10,
          0
        )

      assert result.next_cron_run_dataclip_id == nil
    end

    test "cursor set to job_b, no successful steps: returns nil" do
      project = insert(:project)

      %{trigger: trigger, job_a: job_a, job_b: job_b} =
        build_two_job_cron_workflow(project)

      trigger
      |> Ecto.Changeset.change(%{cron_cursor_job_id: job_b.id})
      |> Lightning.Repo.update!()

      {:ok, result} =
        NewManualRun.search_selectable_dataclips(
          job_a.id,
          "query=+",
          10,
          0
        )

      assert result.next_cron_run_dataclip_id == nil
    end

    test "webhook trigger: returns nil regardless of step history" do
      project = insert(:project)

      webhook_trigger = build(:trigger, type: :webhook)
      job = build(:job)

      workflow =
        build(:workflow, project: project)
        |> with_trigger(webhook_trigger)
        |> with_job(job)
        |> with_edge({webhook_trigger, job})
        |> insert()
        |> with_snapshot()

      job_record = hd(workflow.jobs)

      insert(:step,
        job: job_record,
        input_dataclip: insert(:dataclip, project: project, body: %{}),
        output_dataclip:
          insert(:dataclip,
            project: project,
            body: %{"out" => true},
            type: :step_result
          ),
        exit_reason: "success",
        finished_at: DateTime.utc_now()
      )

      {:ok, result} =
        NewManualRun.search_selectable_dataclips(
          job_record.id,
          "query=+",
          10,
          0
        )

      assert result.next_cron_run_dataclip_id == nil
    end
  end
end
