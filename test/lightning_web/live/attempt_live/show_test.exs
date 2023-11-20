defmodule LightningWeb.AttemptLive.ShowTest do
  use LightningWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Lightning.Factories

  alias Lightning.WorkOrders
  alias Phoenix.LiveView.AsyncResult

  describe "handle_async/3" do
    setup :register_and_log_in_user
    setup :create_project_for_current_user

    test "with exit error", %{conn: conn, project: project} do
      %{triggers: [%{id: webhook_trigger_id}]} =
        insert(:simple_workflow, project: project)

      # Post to webhook
      assert %{"work_order_id" => wo_id} =
               post(conn, "/i/#{webhook_trigger_id}", %{"x" => 1})
               |> json_response(200)

      %{attempts: [%{id: attempt_id}]} =
        WorkOrders.get(wo_id, include: [:attempts])

      {:ok, view, _html} =
        live(conn, ~p"/projects/#{project.id}/attempts/#{attempt_id}")

      %{socket: socket} = :sys.get_state(view.pid)
      initial_async = AsyncResult.loading()
      expected_async = AsyncResult.failed(initial_async, {:exit, "some reason"})

      assert {:noreply, %{assigns: %{log_lines: ^expected_async}}} =
               LightningWeb.AttemptLive.Show.handle_async(
                 :log_lines,
                 {:exit, "some reason"},
                 Map.merge(socket, %{
                   assigns: Map.put(socket.assigns, :log_lines, initial_async)
                 })
               )
    end

    test "lifecycle of an attempt", %{conn: conn, project: project} do
      %{triggers: [%{id: webhook_trigger_id}], jobs: [job_a, job_b | _rest]} =
        insert(:complex_workflow, project: project)

      # Post to webhook
      assert %{"work_order_id" => wo_id} =
               post(conn, "/i/#{webhook_trigger_id}", %{"x" => 1})
               |> json_response(200)

      workorder =
        %{attempts: [%{id: attempt_id} = attempt]} =
        WorkOrders.get(wo_id, include: [:attempts])

      {:ok, view, _html} =
        live(conn, ~p"/projects/#{project.id}/attempts/#{attempt_id}")

      assert view
             |> element("#attempt-detail-#{attempt_id}")
             |> render_async() =~ "Pending",
             "has pending state"

      assert view |> log_is_empty?(attempt)

      refute view
             |> has_element?("#step-list-#{attempt_id} > *"),
             "has no runs"

      attempt =
        Lightning.Repo.update!(
          attempt
          |> Ecto.Changeset.change(%{
            state: :claimed,
            claimed_at: DateTime.utc_now()
          })
        )

      Lightning.Attempts.start_attempt(attempt)

      assert view
             |> element("#attempt-detail-#{attempt_id}")
             |> render_async() =~ "Running",
             "has running state"

      refute view
             |> has_element?("#step-list-#{attempt_id} > *"),
             "has no runs"

      {:ok, run} =
        Lightning.Attempts.start_run(%{
          attempt_id: attempt_id,
          run_id: Ecto.UUID.generate(),
          job_id: job_a.id,
          input_dataclip_id: workorder.dataclip_id
        })

      html = step_list_item(view, attempt, run)

      assert html =~ job_a.name
      assert html =~ "Running"

      add_log(attempt, ["I'm the worker, I'm working!"])

      {:ok, log_line} = add_log({attempt, run}, %{message: "hello"})

      assert view |> has_log_line?("I'm the worker, I'm working!")
      assert view |> has_log_line?(log_line.message)

      view |> select_run(attempt, job_a.name)

      # Check that the input dataclip is rendered
      assert view
             |> element("#run-input-#{run.id}")
             |> render_async()
             |> Floki.parse_fragment!()
             |> Floki.text() =~ ~s({  "x": 1})

      assert view |> output_is_empty?(run)

      # Complete the run
      {:ok, _run} =
        Lightning.Attempts.complete_run(%{
          attempt_id: attempt_id,
          project_id: project.id,
          run_id: run.id,
          output_dataclip: ~s({"y": 2}),
          output_dataclip_id: output_dataclip_id = Ecto.UUID.generate(),
          reason: "success"
        })

      assert view |> run_output(run) =~ ~r/{  \"y\": 2}/

      {:ok, run_2} =
        Lightning.Attempts.start_run(%{
          attempt_id: attempt_id,
          run_id: Ecto.UUID.generate(),
          job_id: job_b.id,
          input_dataclip_id: output_dataclip_id
        })

      html = step_list_item(view, attempt, run)

      assert html =~ job_a.name
      assert html =~ "success"

      html = step_list_item(view, attempt, run_2)

      assert html =~ job_b.name
      assert html =~ "running"

      view |> select_run(attempt, job_b.name)

      assert view |> output_is_empty?(run_2)

      {:ok, _run} =
        Lightning.Attempts.complete_run(%{
          attempt_id: attempt_id,
          project_id: project.id,
          run_id: run_2.id,
          output_dataclip: ~s({"z": 2}),
          output_dataclip_id: Ecto.UUID.generate(),
          reason: "success"
        })

      assert view |> run_output(run_2) =~ ~r/{  \"z\": 2}/

      # Go back to the previous run and check the output gets switched back
      view |> select_run(attempt, job_a.name)
      assert view |> run_output(run) =~ ~r/{  \"y\": 2}/

      {:ok, _} = Lightning.Attempts.complete_attempt(attempt, %{state: :failed})

      assert view
             |> element("#attempt-detail-#{attempt_id}")
             |> render_async() =~ "Failed"
    end
  end

  defp add_log({attempt, run}, message) do
    Lightning.Attempts.append_attempt_log(attempt, %{
      run_id: run.id,
      message: message,
      timestamp: DateTime.utc_now()
    })
  end

  defp add_log(attempt, message) do
    Lightning.Attempts.append_attempt_log(attempt, %{
      message: message,
      timestamp: DateTime.utc_now()
    })
  end

  defp has_log_line?(view, text) do
    view
    |> element("[id^='attempt-log-']:not([id$='-nothing-yet'])")
    |> render_async() =~
      text
      |> Phoenix.HTML.Safe.to_iodata()
      |> to_string()
  end

  defp step_list_item(view, attempt, run) do
    view
    |> element("#step-list-#{attempt.id} > [data-run-id='#{run.id}']")
    |> render_async()
  end

  defp select_run(view, attempt, job_name) do
    view
    |> element("#step-list-#{attempt.id} a[data-phx-link]", job_name)
    |> render_click()
  end

  defp run_output(view, run) do
    assert view
           |> element("#run-output-#{run.id}")
           |> render_async()
           |> Floki.parse_fragment!()
           |> Floki.text()
  end

  defp output_is_empty?(view, run) do
    view
    |> element("#run-output-#{run.id}")
    |> render_async()
    |> Floki.parse_fragment!()
    |> Floki.text() =~
      ~r/^[\n\s]+Nothing yet\.\.\.[\n\s]+$/
  end

  defp log_is_empty?(view, attempt) do
    view
    |> element("#attempt-log-#{attempt.id}")
    |> render_async()
    |> Floki.parse_fragment!()
    |> Floki.text() =~
      ~r/^[\n\s]+Nothing yet\.\.\.[\n\s]+$/
  end
end
