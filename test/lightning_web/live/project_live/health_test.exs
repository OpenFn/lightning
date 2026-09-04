defmodule LightningWeb.ProjectLive.HealthTest do
  use LightningWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Lightning.Factories

  setup :register_and_log_in_user
  setup :create_project_for_current_user

  test "renders the project name and mounts the React page", %{
    conn: conn,
    project: project
  } do
    {:ok, _view, html} = live(conn, ~p"/projects/#{project.id}/health")

    assert html =~ project.name
    assert html =~ ~s(data-react-name="ProjectHealth")
    assert html =~ ~s(data-project-id="#{project.id}")
  end

  test "redirects a user who is not a member of the project", %{conn: conn} do
    other = insert(:project)

    assert {:error, {:redirect, %{to: "/projects"}}} =
             live(conn, ~p"/projects/#{other.id}/health")
  end
end
