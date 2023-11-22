defmodule LightningWeb.AttemptLive.ShowTest do
  use LightningWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Lightning.Factories

  alias Lightning.Attempts
  alias Lightning.WorkOrders
  alias Phoenix.LiveView.AsyncResult

  describe "handle_async/3" do
    setup :register_and_log_in_superuser
    setup :create_project_for_current_user

    @tag :skip
    test "with exit error", %{conn: conn, project: project} do
      %{triggers: [%{id: webhook_trigger_id}], jobs: [job]} =
        insert(:simple_workflow, project: project)

      # Post to webhook
      conn = post(conn, "/i/#{webhook_trigger_id}", %{"x" => 1})
      %{"work_order_id" => wo_id} = json_response(conn, 200)

      %{attempts: [attempt]} =
        WorkOrders.get(wo_id, include: [:attempts])

      # other attempt run
      insert(:attempt_run,
        run:
          build(:run,
            job: job,
            input_dataclip: build(:dataclip),
            output_dataclip: build(:dataclip)
          ),
        attempt: attempt
      )

      %{runs: [run_id]} = Attempts.get(attempt.id, include: [:runs])

      {:ok, view, _html} =
        live(conn, ~p"/projects/#{project.id}/runs/#{run_id}")

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
  end
end
