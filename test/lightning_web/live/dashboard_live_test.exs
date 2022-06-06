defmodule LightningWeb.DashboardLiveTest do
  use LightningWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  setup :register_and_log_in_user
  setup :create_project_for_current_user

  describe "Index" do
    test "lists all projects", %{
      conn: conn,
      project: project
    } do
      {:ok, view, html} = live(conn, Routes.dashboard_index_path(conn, :index))

      assert html =~ "Projects"

      view
      |> element(~s{a[data-phx-link=redirect]#project-#{project.id}})
      |> render_click()

      assert_redirect(
        view,
        Routes.project_dashboard_index_path(conn, :show, project.id)
      )
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
             |> render_hook("component.mounted")

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
    end
  end
end
