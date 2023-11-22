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

    test "with exit error", %{conn: conn, project: project} do
      %{triggers: [%{id: webhook_trigger_id}], jobs: [job]} =
        insert(:simple_workflow, project: project)

      # Post to webhook
      post(conn, "/i/#{webhook_trigger_id}", %{"x" => 1})
      %{"work_order_id" => wo_id} = json_response(conn, 200)

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
  end
end
