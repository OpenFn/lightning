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

  describe "Edit" do
    # import SweetXml
    # test "if project A has 6 jobs, the dropdown list displays 5 jobs (all existing jobs minus the one that the user is currently on)",
    #      %{
    #        conn: conn,
    #        project: project,
    #        job: job
    #      } do
    #   # We are adding 5 more jobs to the current project. It will now have 6 jobs (a job is already assigned to it in the setup of this test)
    #   n_jobs = 5

    #   new_jobs =
    #     for _ <- 1..n_jobs,
    #         do:
    #           job_fixture(name: "some other name", workflow_id: job.workflow_id)

    #   assert Jobs.jobs_for_project(project)
    #          |> Enum.count() == n_jobs + 1

    #   {:ok, index_live, _html} =
    #     live(conn, Routes.project_job_index_path(conn, :index, project.id))

    #   {:ok, form_live, _} =
    #     index_live
    #     |> element("#job-#{job.id} a", "Edit")
    #     |> render_click()
    #     |> follow_redirect(
    #       conn,
    #       Routes.project_job_edit_path(
    #         conn,
    #         :edit,
    #         project.id,
    #         job
    #       )
    #     )

    #   assert form_live
    #          |> form("#job-form", job_form: %{trigger_type: "on_job_success"})
    #          |> render_change()

    #   displayed_jobs =
    #     form_live
    #     |> element("#upstreamJob")
    #     |> render()
    #     |> parse()
    #     |> xpath(~x"option/text()"l)

    #   displayed_jobs =
    #     displayed_jobs |> Enum.map(fn job_name -> "#{job_name}" end)

    #   assert displayed_jobs |> Enum.count() == n_jobs
    #   assert displayed_jobs == Enum.map(new_jobs, fn job -> job.name end)
    #   refute Enum.member?(displayed_jobs, job.name)
    # end
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
