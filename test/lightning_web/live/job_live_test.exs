defmodule LightningWeb.JobLiveTest do
  use LightningWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Lightning.JobsFixtures
  import Lightning.ProjectsFixtures
  import Lightning.CredentialsFixtures

  alias LightningWeb.JobLive.AdaptorPicker

  setup :register_and_log_in_user
  setup :create_project_for_current_user

  setup %{project: project} do
    project_credential_fixture(project_id: project.id)
    job = workflow_job_fixture(project_id: project.id)
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

  describe "The adaptor picker" do
    test "abbreviates standard adaptors via display_name_for_adaptor/1" do
      assert AdaptorPicker.display_name_for_adaptor("@openfn/language-abc") ==
               {"abc", "@openfn/language-abc"}

      assert AdaptorPicker.display_name_for_adaptor("@openfn/adaptor-xyz") ==
               "@openfn/adaptor-xyz"

      assert AdaptorPicker.display_name_for_adaptor("@other_org/some_module") ==
               "@other_org/some_module"
    end
  end

  describe "Deleting a job from inspector" do
    test "jobs with no downstream jobs can be deleted", %{
      conn: conn,
      project: project,
      job: job
    } do
      {:ok, view, html} =
        live(
          conn,
          Routes.project_workflow_path(
            conn,
            :edit_job,
            project.id,
            job.workflow_id,
            job.id
          )
        )

      assert html =~ project.name

      assert has_element?(view, "#delete-job")

      view
      |> element("#delete-job")
      |> render_click()

      assert_patch(
        view,
        Routes.project_workflow_path(conn, :show, project.id, job.workflow_id)
      )
    end

    test "jobs with downstream jobs can't be deleted", %{
      conn: conn,
      project: project,
      job: job
    } do
      workflow_job_fixture(
        trigger: %{type: "on_job_success", upstream_job_id: job.id}
      )

      {:ok, view, html} =
        live(
          conn,
          Routes.project_workflow_path(
            conn,
            :edit_job,
            project.id,
            job.workflow_id,
            job.id
          )
        )

      assert html =~ project.name

      assert has_element?(
               view,
               "button#delete-job[disabled, title='Impossible to delete upstream jobs. Please delete all associated downstream jobs first.']"
             )
    end
  end
end
