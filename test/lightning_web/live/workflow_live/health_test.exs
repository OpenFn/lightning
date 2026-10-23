defmodule LightningWeb.WorkflowLive.HealthTest do
  use LightningWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Lightning.Factories
  import LightningWeb.DesignSystemHelpers

  alias Lightning.Repo

  @page "#workflow-health-page"

  setup :register_and_log_in_user
  setup :create_project_for_current_user

  test "gives the page the project and the workflow", %{
    conn: conn,
    project: project
  } do
    workflow = insert(:workflow, project: project)

    {:ok, view, _html} =
      live(conn, ~p"/projects/#{project.id}/w/#{workflow.id}/health")

    props = page_props(view, @page)

    assert props["workflow"] == %{"id" => workflow.id, "name" => workflow.name}
    assert props["project"]["id"] == project.id
    assert props["projectLabel"] == project.name
  end

  test "shows the book-a-demo banner when it is on", %{
    conn: conn,
    project: project
  } do
    Mox.stub(Lightning.MockConfig, :book_demo_banner_enabled?, fn -> true end)
    workflow = insert(:workflow, project: project)

    {:ok, view, _html} =
      live(conn, ~p"/projects/#{project.id}/w/#{workflow.id}/health")

    assert has_element?(view, "#book-demo-banner")
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

  test "passes the project's history retention period, or nil when history is kept forever",
       %{conn: conn, project: project} do
    workflow = insert(:workflow, project: project)
    path = ~p"/projects/#{project.id}/w/#{workflow.id}/health"

    {:ok, view, _html} = live(conn, path)
    assert page_props(view, @page)["project"]["historyRetentionPeriod"] == nil

    project
    |> Ecto.Changeset.change(history_retention_period: 14)
    |> Repo.update!()

    {:ok, view, _html} = live(conn, path)
    assert page_props(view, @page)["project"]["historyRetentionPeriod"] == 14
  end
end
