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

  describe "The trigger type select list" do
    test "should only display webhook or cron for the first job in a workflow",
         %{
           conn: conn,
           project: project,
           job: job
         } do
      assert job.trigger.type == :webhook

      {:ok, view, _html} =
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

      assert has_element?(
               view,
               "select#triggerType option[value=webhook]"
             )

      assert has_element?(
               view,
               "select#triggerType option[value=cron]"
             )

      refute has_element?(
               view,
               "select#triggerType option[value=on_job_success]"
             )

      refute has_element?(
               view,
               "select#triggerType option[value=on_job_failure]"
             )
    end

    test "should only display on_job_success or on_job_failure for downstream jobs in a workflow",
         %{
           conn: conn,
           project: project,
           job: job
         } do
      other_job =
        job_fixture(
          trigger: %{type: :on_job_failure, upstream_job_id: job.id},
          workflow_id: job.workflow_id
        )

      assert other_job.trigger.type == :on_job_failure

      {:ok, view, _html} =
        live(
          conn,
          Routes.project_workflow_path(
            conn,
            :edit_job,
            project.id,
            other_job.workflow_id,
            other_job.id
          )
        )

      assert has_element?(
               view,
               "select#triggerType option[value=on_job_failure]"
             )

      assert has_element?(
               view,
               "select#triggerType option[value=on_job_success]"
             )

      refute has_element?(
               view,
               "select#triggerType option[value=webhook]"
             )

      refute has_element?(
               view,
               "select#triggerType option[value=cron]"
             )
    end
  end
end
