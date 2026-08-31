defmodule LightningWeb.WorkflowLive.HealthTest do
  use LightningWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Lightning.Factories

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
end
