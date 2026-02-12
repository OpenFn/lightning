defmodule LightningWeb.RunLive.ShowTest do
  use LightningWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Lightning.Factories
  import Lightning.WorkflowLive.Helpers

  alias Lightning.WorkOrders
  alias Phoenix.LiveView.AsyncResult

  setup :stub_rate_limiter_ok

  describe "handle_async/3" do
    setup :register_and_log_in_user
    setup :create_project_for_current_user

    test "with exit error", %{conn: conn, project: project} do
      %{triggers: [%{id: webhook_trigger_id}]} =
        insert(:simple_workflow, project: project) |> with_snapshot()

      # Post to webhook
      assert post(conn, "/i/#{webhook_trigger_id}", %{"x" => 1})
             |> json_response(200)

      # Try to fetch a run that doesn't exist
      {:ok, view, _html} =
        live(conn, ~p"/projects/#{project.id}/runs/#{Ecto.UUID.generate()}")

      view |> render_async()

      %{socket: socket} = :sys.get_state(view.pid)

      assert %AsyncResult{ok?: false, failed: :not_found} =
               socket.assigns.run
    end

    test "lifecycle of a run", %{conn: conn, project: project} do
      %{triggers: [%{id: webhook_trigger_id}], jobs: [job_a, job_b | _rest]} =
        insert(:complex_workflow, project: project) |> with_snapshot()

      # Post to webhook
      assert %{"work_order_id" => wo_id} =
               post(conn, "/i/#{webhook_trigger_id}", %{"x" => 1})
               |> json_response(200)

      workorder =
        %{runs: [%{id: run_id} = run]} =
        WorkOrders.get(wo_id, include: [:runs])

      {:ok, view, _html} =
        live(conn, ~p"/projects/#{project.id}/runs/#{run_id}")

      assert view
             |> element("#run-detail-#{run_id}")
             |> render_async() =~ "Enqueued",
             "has enqueued state"

      # Check that webhook-triggered run shows "Webhook trigger" as the starter
      assert view
             |> element("#run-detail-#{run_id}")
             |> render_async() =~ "Webhook trigger",
             "shows webhook trigger as starter"

      assert has_element?(
               view,
               "div#log-panel [phx-hook='LogViewer'][data-run-id='#{run_id}']"
             )

      refute view
             |> has_element?("#step-list-#{run_id} > *"),
             "has no steps"

      run =
        Lightning.Repo.update!(
          run
          |> Ecto.Changeset.change(%{
            state: :claimed,
            claimed_at: DateTime.utc_now()
          })
        )

      Lightning.Runs.start_run(run)

      assert view
             |> element("#run-detail-#{run_id}")
             |> render_async() =~ "Running",
             "has running state"

      refute view
             |> has_element?("#step-list-#{run_id} > *"),
             "has no steps"

      {:ok, step} =
        Lightning.Runs.start_step(run, %{
          step_id: Ecto.UUID.generate(),
          job_id: job_a.id,
          input_dataclip_id: input_dataclip_id = workorder.dataclip_id
        })

      html = step_list_item(view, run, step)

      assert html =~ job_a.name

      assert html =~
               "data-start-time=\"#{DateTime.to_unix(step.started_at, :millisecond)}\""

      {:ok, log_line_1} = add_log(run, ["I'm the worker, I'm working!"])

      {:ok, log_line_2} = add_log({run, step}, %{message: "hello"})

      event_name = "logs-#{run.id}"

      assert_push_event(view, ^event_name, %{logs: [^log_line_1]})
      assert_push_event(view, ^event_name, %{logs: [^log_line_2]})

      view |> select_step(run, job_a.name)

      input_dataclip_viewer =
        view
        |> dataclip_viewer("step-input-dataclip-viewer")
        |> get_attrs_and_inner_html()
        |> decode_inner_json()

      # Check that the input dataclip is rendered
      assert {_attrs, %{"dataclipId" => ^input_dataclip_id}} =
               input_dataclip_viewer

      assert view |> output_is_empty?(step)

      # Complete the step
      {:ok, step} =
        Lightning.Runs.complete_step(%{
          run_id: run_id,
          project_id: project.id,
          step_id: step.id,
          output_dataclip: ~s({"y": 2}),
          output_dataclip_id: output_dataclip_id = Ecto.UUID.generate(),
          reason: "success"
        })

      # Check that the output dataclip is rendered
      output_dataclip_viewer =
        view
        |> dataclip_viewer("step-output-dataclip-viewer")
        |> get_attrs_and_inner_html()
        |> decode_inner_json()

      # Check that the output dataclip is rendered
      assert {_attrs, %{"dataclipId" => ^output_dataclip_id}} =
               output_dataclip_viewer

      {:ok, step_2} =
        Lightning.Runs.start_step(run, %{
          step_id: Ecto.UUID.generate(),
          job_id: job_b.id,
          input_dataclip_id: output_dataclip_id
        })

      html = step_list_item(view, run, step)

      assert html =~ job_a.name
      assert html =~ "text-green-500"

      html = step_list_item(view, run, step_2)

      assert html =~ job_b.name

      assert html =~
               "data-start-time=\"#{DateTime.to_unix(step_2.started_at, :millisecond)}\""

      view |> select_step(run, job_b.name)

      assert view |> output_is_empty?(step_2)

      {:ok, _step_2} =
        Lightning.Runs.complete_step(%{
          run_id: run_id,
          project_id: project.id,
          step_id: step_2.id,
          output_dataclip: ~s({"z": 2}),
          output_dataclip_id: step_2_output_dataclip_id = Ecto.UUID.generate(),
          reason: "success"
        })

      output_dataclip_viewer =
        view
        |> dataclip_viewer("step-output-dataclip-viewer")
        |> get_attrs_and_inner_html()
        |> decode_inner_json()

      assert {_attrs, %{"dataclipId" => ^step_2_output_dataclip_id}} =
               output_dataclip_viewer

      # Go back to the previous step and check the output gets switched back
      view |> select_step(run, job_a.name)

      output_dataclip_viewer =
        view
        |> dataclip_viewer("step-output-dataclip-viewer")
        |> get_attrs_and_inner_html()
        |> decode_inner_json()

      assert {_attrs, %{"dataclipId" => ^output_dataclip_id}} =
               output_dataclip_viewer

      {:ok, _} = Lightning.Runs.complete_run(run, %{state: "failed"})

      assert view
             |> element("#run-detail-#{run_id}")
             |> render_async() =~ "Failed"
    end
  end

  defp add_log({run, step}, message) do
    Lightning.Runs.append_run_log(run, %{
      step_id: step.id,
      message: message,
      timestamp: DateTime.utc_now()
    })
  end

  defp add_log(run, message) do
    Lightning.Runs.append_run_log(run, %{
      message: message,
      timestamp: DateTime.utc_now()
    })
  end

  defp step_list_item(view, run, step) do
    view
    |> element("#step-list-#{run.id} > [data-step-id='#{step.id}']")
    |> render_async()
  end

  describe "workflow link" do
    setup :register_and_log_in_user
    setup :create_project_for_current_user

    test "excludes version param when run snapshot matches current workflow", %{
      conn: conn,
      project: project
    } do
      workflow = insert(:simple_workflow, project: project) |> with_snapshot()
      %{triggers: [%{id: webhook_trigger_id}]} = workflow

      # Post to webhook to create a run
      assert %{"work_order_id" => wo_id} =
               post(conn, "/i/#{webhook_trigger_id}", %{"x" => 1})
               |> json_response(200)

      %{runs: [%{id: run_id}]} = WorkOrders.get(wo_id, include: [:runs])

      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/runs/#{run_id}")

      html = view |> element("#run-detail-#{run_id}") |> render_async()

      # Find the workflow link - should NOT include version param
      assert html =~
               ~r/href="\/projects\/#{project.id}\/w\/#{workflow.id}\?run=#{run_id}"/

      refute html =~ ~r/&v=/
    end

    test "includes version param when run snapshot differs from current workflow",
         %{
           conn: conn,
           project: project
         } do
      # Create workflow with initial snapshot
      workflow =
        insert(:simple_workflow, project: project, lock_version: 1)
        |> with_snapshot()

      %{triggers: [%{id: webhook_trigger_id}]} = workflow

      # Post to webhook to create a run on v1
      assert %{"work_order_id" => wo_id} =
               post(conn, "/i/#{webhook_trigger_id}", %{"x" => 1})
               |> json_response(200)

      %{runs: [%{id: run_id}], snapshot: snapshot} =
        WorkOrders.get(wo_id, include: [:runs, :snapshot])

      # Update workflow to v2 (simulating a change after the run was created)
      workflow =
        Lightning.Repo.update!(Ecto.Changeset.change(workflow, lock_version: 2))

      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/runs/#{run_id}")

      html = view |> element("#run-detail-#{run_id}") |> render_async()

      # Find the workflow link - should include version param
      # Note: & is HTML-escaped as &amp; in rendered output
      assert html =~
               ~r/href="\/projects\/#{project.id}\/w\/#{workflow.id}\?run=#{run_id}&amp;v=#{snapshot.lock_version}"/
    end
  end

  defp select_step(view, run, job_name) do
    view
    |> element("#step-list-#{run.id} a[data-phx-link]", job_name)
    |> render_click()
  end

  defp output_is_empty?(view, step) do
    view
    |> has_element?("#step-output-#{step.id}-nothing-yet")
  end
end
