defmodule LightningWeb.WorkflowLive.HealthTest do
  use LightningWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Lightning.Factories

  alias Lightning.WorkOrders.Events

  setup :register_and_log_in_user
  setup :create_project_for_current_user

  test "renders the workflow name", %{conn: conn, project: project} do
    workflow = insert(:workflow, project: project)

    {:ok, _view, html} =
      live(conn, ~p"/projects/#{project.id}/w/#{workflow.id}/health")

    assert html =~ workflow.name
  end

  test "redirects when the workflow is in another project", %{
    conn: conn,
    project: project
  } do
    other = insert(:workflow)

    assert {:error, {:redirect, %{to: to, flash: flash}}} =
             live(conn, ~p"/projects/#{project.id}/w/#{other.id}/health")

    assert to == ~p"/projects/#{project.id}/w"
    assert flash["error"] == "Workflow not found"
  end

  describe "refresh" do
    setup %{conn: conn, project: project} do
      workflow = insert(:workflow, project: project)

      {:ok, view, _html} =
        live(conn, ~p"/projects/#{project.id}/w/#{workflow.id}/health")

      %{view: view, workflow: workflow, project: project}
    end

    test "tells the page to refresh when a work order settles", ctx do
      %{view: view, workflow: workflow, project: project} = ctx

      # Cached from an earlier reader. The refresh is a lie unless this goes
      # with it, since the next request would be answered out of it.
      Lightning.Workflows.Stats.outcomes(workflow)

      settle(project, workflow, :failed)

      assert_push_event(view, "health:changed", %{})

      assert {:ok, nil} =
               Cachex.get(:workflow_stats, {:outcomes, workflow.id, 30})
    end

    test "stays quiet for a work order that has not settled yet", ctx do
      %{view: view, workflow: workflow, project: project} = ctx

      settle(project, workflow, :running)

      refute_push_event(view, "health:changed", %{})
    end

    test "stays quiet for another workflow's work orders", ctx do
      %{view: view, project: project} = ctx
      other = insert(:workflow, project: project)

      settle(project, other, :failed)

      refute_push_event(view, "health:changed", %{})
    end

    test "collapses a burst into one push now and one when the window closes",
         ctx do
      %{view: view, workflow: workflow, project: project} = ctx

      for _ <- 1..5, do: settle(project, workflow, :failed)

      assert_push_event(view, "health:changed", %{})
      refute_push_event(view, "health:changed", %{})

      # Stands in for the throttle's own timer, so the test doesn't sit out the
      # window.
      send(view.pid, :refresh_window_closed)

      assert_push_event(view, "health:changed", %{})

      # Window closed clean this time: nothing settled since the last push.
      send(view.pid, :refresh_window_closed)

      refute_push_event(view, "health:changed", %{})
    end
  end

  defp settle(project, workflow, state) do
    work_order =
      insert(:workorder, workflow: workflow, state: state, snapshot: nil)

    Events.work_order_updated(project.id, work_order)
  end
end
