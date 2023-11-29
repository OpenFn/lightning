defmodule LightningWeb.AttemptLive.AttemptViewerLiveTest do
  use LightningWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Lightning.Factories

  alias Phoenix.LiveView.AsyncResult

  setup :register_and_log_in_user
  setup :create_project_for_current_user

  describe "handle_async/3" do
    test "with exit error", %{conn: conn, project: project} do
      %{id: workflow_id, jobs: [job]} = insert(:simple_workflow)

      {:ok, view, _html} =
        live(conn, ~p"/projects/#{project.id}/w/#{workflow_id}?s=#{job.id}")

      %{socket: socket} = :sys.get_state(view.pid)
      initial_async = AsyncResult.loading()
      expected_async = AsyncResult.failed(initial_async, {:exit, "some reason"})

      assert {:noreply, %{assigns: %{initial_log_lines: ^expected_async}}} =
               LightningWeb.AttemptLive.AttemptViewerLive.handle_async(
                 :initial_log_lines,
                 {:exit, "some reason"},
                 Map.merge(socket, %{
                   assigns:
                     Map.put(socket.assigns, :initial_log_lines, initial_async)
                 })
               )
    end
  end
end
