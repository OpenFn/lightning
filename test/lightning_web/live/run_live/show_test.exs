defmodule LightningWeb.RunLive.ShowTest do
  use LightningWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Lightning.Factories

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
          input_dataclip_id: workorder.dataclip_id
        })

      html = step_list_item(view, run, step)

      assert html =~ job_a.name
      assert html =~ "Running"

      {:ok, log_line_1} = add_log(run, ["I'm the worker, I'm working!"])

      {:ok, log_line_2} = add_log({run, step}, %{message: "hello"})

      event_name = "logs-#{run.id}"

      assert_push_event(view, ^event_name, %{logs: [^log_line_1]})
      assert_push_event(view, ^event_name, %{logs: [^log_line_2]})

      view |> select_step(run, job_a.name)

      # Check that the input dataclip is rendered
      assert view
             |> render_async()
             |> Floki.parse_fragment!()
             |> Floki.find(
               "[phx-hook='DataclipViewer'][data-id='#{step.input_dataclip_id}']"
             )
             |> Enum.count() == 1

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

      assert view
             |> render_async()
             |> Floki.parse_fragment!()
             |> Floki.find(
               "[phx-hook='DataclipViewer'][data-id='#{step.output_dataclip_id}']"
             )
             |> Enum.count() == 1

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
      assert html =~ "Running..."

      view |> select_step(run, job_b.name)

      assert view |> output_is_empty?(step_2)

      {:ok, step_2} =
        Lightning.Runs.complete_step(%{
          run_id: run_id,
          project_id: project.id,
          step_id: step_2.id,
          output_dataclip: ~s({"z": 2}),
          output_dataclip_id: Ecto.UUID.generate(),
          reason: "success"
        })

      assert view
             |> render_async()
             |> Floki.parse_fragment!()
             |> Floki.find(
               "[phx-hook='DataclipViewer'][data-id='#{step_2.output_dataclip_id}']"
             )
             |> Enum.count() == 1

      # Go back to the previous step and check the output gets switched back
      view |> select_step(run, job_a.name)

      assert view
             |> render_async()
             |> Floki.parse_fragment!()
             |> Floki.find(
               "[phx-hook='DataclipViewer'][data-id='#{step.output_dataclip_id}']"
             )
             |> Enum.count() == 1

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
