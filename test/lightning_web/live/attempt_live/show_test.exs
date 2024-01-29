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
      assert post(conn, "/i/#{webhook_trigger_id}", %{"x" => 1})
             |> json_response(200)

      # Try to fetch a run that doesn't exist
      {:ok, view, _html} =
        live(conn, ~p"/projects/#{project.id}/runs/#{Ecto.UUID.generate()}")

      view |> render_async()

      %{socket: socket} = :sys.get_state(view.pid)

      assert %AsyncResult{ok?: false, failed: :not_found} =
               socket.assigns.attempt
    end

    test "lifecycle of a run", %{conn: conn, project: project} do
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
        live(conn, ~p"/projects/#{project.id}/runs/#{attempt_id}")

      assert view
             |> element("#attempt-detail-#{attempt_id}")
             |> render_async() =~ "Enqueued",
             "has enqueued state"

      assert view |> log_is_empty?(attempt)

      refute view
             |> has_element?("#step-list-#{attempt_id} > *"),
             "has no steps"

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
             "has no steps"

      {:ok, step} =
        Lightning.Attempts.start_step(%{
          attempt_id: attempt_id,
          step_id: Ecto.UUID.generate(),
          job_id: job_a.id,
          input_dataclip_id: workorder.dataclip_id
        })

      html = step_list_item(view, attempt, step)

      assert html =~ job_a.name
      assert html =~ "Running"

      add_log(attempt, ["I'm the worker, I'm working!"])

      {:ok, log_line} = add_log({attempt, step}, %{message: "hello"})

      assert view |> has_log_line?("I'm the worker, I'm working!")
      assert view |> has_log_line?(log_line.message)

      view |> select_step(attempt, job_a.name)

      # Check that the input dataclip is rendered
      assert view
             |> element("#step-input-#{step.id}")
             |> render_async()
             |> Floki.parse_fragment!()
             |> Floki.text() =~
               ~s({  \"data\": {    \"x\": 1  },  \"request\": {    \"headers\": {      \"content-type\": \"multipart/mixed; boundary=plug_conn_test\"    })

      assert view |> output_is_empty?(step)

      # Complete the step
      {:ok, _step} =
        Lightning.Attempts.complete_step(%{
          attempt_id: attempt_id,
          project_id: project.id,
          step_id: step.id,
          output_dataclip: ~s({"y": 2}),
          output_dataclip_id: output_dataclip_id = Ecto.UUID.generate(),
          reason: "success"
        })

      assert view |> step_output(step) =~ ~r/{  \"y\": 2}/

      {:ok, step_2} =
        Lightning.Attempts.start_step(%{
          attempt_id: attempt_id,
          step_id: Ecto.UUID.generate(),
          job_id: job_b.id,
          input_dataclip_id: output_dataclip_id
        })

      html = step_list_item(view, attempt, step)

      assert html =~ job_a.name
      assert html =~ "success"

      html = step_list_item(view, attempt, step_2)

      assert html =~ job_b.name
      assert html =~ "running"

      view |> select_step(attempt, job_b.name)

      assert view |> output_is_empty?(step_2)

      {:ok, _step} =
        Lightning.Attempts.complete_step(%{
          attempt_id: attempt_id,
          project_id: project.id,
          step_id: step_2.id,
          output_dataclip: ~s({"z": 2}),
          output_dataclip_id: Ecto.UUID.generate(),
          reason: "success"
        })

      assert view |> step_output(step_2) =~ ~r/{  \"z\": 2}/

      # Go back to the previous step and check the output gets switched back
      view |> select_step(attempt, job_a.name)
      assert view |> step_output(step) =~ ~r/{  \"y\": 2}/

      {:ok, _} = Lightning.Attempts.complete_attempt(attempt, %{state: :failed})

      assert view
             |> element("#attempt-detail-#{attempt_id}")
             |> render_async() =~ "Failed"
    end
  end

  defp add_log({attempt, step}, message) do
    Lightning.Attempts.append_attempt_log(attempt, %{
      step_id: step.id,
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

  defp step_list_item(view, attempt, step) do
    view
    |> element("#step-list-#{attempt.id} > [data-step-id='#{step.id}']")
    |> render_async()
  end

  defp select_step(view, attempt, job_name) do
    view
    |> element("#step-list-#{attempt.id} a[data-phx-link]", job_name)
    |> render_click()
  end

  defp step_output(view, step) do
    assert view
           |> element("#step-output-#{step.id}")
           |> render_async()
           |> Floki.parse_fragment!()
           |> Floki.text()
  end

  defp output_is_empty?(view, step) do
    view
    |> element("#step-output-#{step.id}")
    |> has_nothing_yet?()
  end

  defp log_is_empty?(view, attempt) do
    view
    |> element("#attempt-log-#{attempt.id}")
    |> has_nothing_yet?()
  end

  defp has_nothing_yet?(elem) do
    elem
    |> render_async()
    |> Floki.parse_fragment!()
    |> Floki.filter_out("[id$='-type']")
    |> Floki.text() =~
      ~r/^[\n\s]+Nothing yet[\n\s]+$/
  end
end
