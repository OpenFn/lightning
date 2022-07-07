defmodule LightningWeb.DashboardLiveTest do
  use LightningWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  setup :register_and_log_in_user
  setup :create_project_for_current_user

  describe "Index" do
    setup :register_and_log_in_user

    test "User is assigned no project", %{
      conn: conn
    } do
      {:ok, _view, html} = live(conn, Routes.dashboard_index_path(conn, :index))

      assert html =~ "No project found, please talk to your administrator."
    end
  end

  describe "Index redirects to show" do
    setup :register_and_log_in_user
    setup :create_project_for_current_user

    test "User is assigned a project, should redirect", %{
      conn: conn,
      user: user,
      project: project
    } do
      {:ok, _view, html} =
        live(conn, Routes.dashboard_index_path(conn, :index))
        |> follow_redirect(
          conn,
          Routes.project_dashboard_index_path(conn, :show, project.id)
        )

      assert html =~ "WorkflowDiagram"
    end
  end

  describe "Show" do
    import Lightning.JobsFixtures

    setup %{project: project} do
      %{job: job_fixture(project_id: project.id)}
    end

    test "renders the workflow diagram", %{
      conn: conn,
      project: project,
      job: job
    } do
      {:ok, view, html} =
        live(conn, Routes.project_dashboard_index_path(conn, :show, project.id))

      assert html =~ project.name

      assert view
             |> element("div#hook-#{project.id}[phx-update=ignore]")
             |> render_hook("component_mounted")

      expected_project_space = %{
        "jobs" => [
          %{
            "adaptor" => "@openfn/language-common",
            "id" => job.id,
            "name" => job.name,
            "trigger" => %{"type" => :webhook, "upstreamJob" => nil}
          }
        ]
      }

      assert_push_event(view, "update_project_space", ^expected_project_space)

      view
      |> render_patch(
        Routes.project_dashboard_index_path(conn, :show, project.id, %{
          selected: job.id
        })
      )

      assert has_element?(view, "#job-#{job.id}")
    end
  end
end
