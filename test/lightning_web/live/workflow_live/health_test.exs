defmodule LightningWeb.WorkflowLive.HealthTest do
  use LightningWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Lightning.Factories

  alias Lightning.Repo

  setup :register_and_log_in_user
  setup :create_project_for_current_user

  test "renders the workflow name", %{conn: conn, project: project} do
    workflow = insert(:workflow, project: project)

    {:ok, _view, html} =
      live(conn, ~p"/projects/#{project.id}/w/#{workflow.id}/health")

    assert html =~ workflow.name
  end

  test "the workflow crumb leads back to its editor", %{
    conn: conn,
    project: project
  } do
    workflow = insert(:workflow, project: project)

    {:ok, view, _html} =
      live(conn, ~p"/projects/#{project.id}/w/#{workflow.id}/health")

    assert view
           |> element("nav[aria-label='Breadcrumbs'] a", workflow.name)
           |> render() =~ ~p"/projects/#{project.id}/w/#{workflow.id}"
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

  test "passes the project's history retention period to the React component",
       %{conn: conn, project: project} do
    workflow = insert(:workflow, project: project)

    project
    |> Ecto.Changeset.change(history_retention_period: 14)
    |> Repo.update!()

    {:ok, _view, html} =
      live(conn, ~p"/projects/#{project.id}/w/#{workflow.id}/health")

    assert html =~ ~s(data-history-retention-period="14")
  end

  test "leaves the retention period off when the project keeps history forever",
       %{conn: conn, project: project} do
    workflow = insert(:workflow, project: project)

    {:ok, _view, html} =
      live(conn, ~p"/projects/#{project.id}/w/#{workflow.id}/health")

    refute html =~ "data-history-retention-period"
  end
end
