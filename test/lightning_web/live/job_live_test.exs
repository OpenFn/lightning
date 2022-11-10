defmodule LightningWeb.JobLiveTest do
  use LightningWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Lightning.JobsFixtures
  import Lightning.ProjectsFixtures
  import Lightning.CredentialsFixtures

  setup :register_and_log_in_user
  setup :create_project_for_current_user

  setup %{project: project} do
    project_credential_fixture(project_id: project.id)
    job = job_fixture(project_id: project.id)
    %{job: job}
  end

  describe "Index" do
    test "lists all jobs", %{conn: conn, job: job, project: project} do
      other_job = job_fixture(name: "other job")

      {:ok, view, html} =
        live(conn, Routes.project_job_index_path(conn, :index, project.id))

      assert html =~ "Jobs"

      table = view |> element("section#inner_content") |> render()
      assert table =~ "job-#{job.id}"
      refute table =~ "job-#{other_job.id}"
    end

    test "deletes job in listing", %{conn: conn, job: job, project: project} do
      {:ok, index_live, _html} =
        live(conn, Routes.project_job_index_path(conn, :index, project.id))

      assert index_live
             |> element("#job-#{job.id} a", "Delete")
             |> render_click()

      refute has_element?(index_live, "#job-#{job.id}")
    end
  end

  describe "Access Jobs Page" do
    test "a user can't access the jobs page when they are not members of that project",
         %{conn: conn} do
      project = project_fixture()

      assert {:error, {:redirect, %{flash: %{"nav" => :no_access}, to: "/"}}} ==
               live(
                 conn,
                 Routes.project_job_index_path(conn, :index, project.id)
               )
    end
  end
end
