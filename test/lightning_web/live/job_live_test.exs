defmodule LightningWeb.JobLiveTest do
  use LightningWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Lightning.JobsFixtures
  import Lightning.CredentialsFixtures
  import Lightning.WorkflowsFixtures
  import SweetXml

  alias LightningWeb.JobLive.AdaptorPicker

  setup :register_and_log_in_user
  setup :create_project_for_current_user

  setup %{project: project} do
    project_credential_fixture(project_id: project.id)
    %{job: job} = workflow_job_fixture(project_id: project.id)
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

    test "adaptor name and version defaults to common and latest", %{
      conn: conn,
      project: project
    } do
      workflow = workflow_fixture(name: "the workflow", project_id: project.id)

      {:ok, view, _html} =
        live(
          conn,
          Routes.project_workflow_path(conn, :new_job, project.id, workflow.id)
        )

      assert view |> element("#adaptor-name") |> has_element?()
      assert view |> element("#adaptor-version") |> has_element?()

      assert view
             |> element("#adaptor-name")
             |> render()
             |> parse()
             |> xpath(~x"option[@selected]/text()"l)
             |> to_string() == "common"

      assert view
             |> element("#adaptor-version")
             |> render()
             |> parse()
             |> xpath(~x"option[@selected]/text()"l)
             |> to_string() == "latest (≥ 1.6.2)"
    end
  end

  describe "JobBuilder events" do
    test "request_metadata", %{conn: conn, project: project} do
      workflow = workflow_fixture(name: "the workflow", project_id: project.id)

      {:ok, view, _html} =
        live(conn, ~p"/projects/#{project.id}/w/#{workflow.id}/j/new")

      assert has_element?(view, "#builder-new")

      assert view
             |> with_target("#builder-new")
             |> render_click("request_metadata", %{})

      assert_push_event(view, "metadata_ready", %{"error" => "no_credential"})
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

      assert has_element?(view, "#delete_job")

      view
      |> element("#delete_job")
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
               "button#delete_job[disabled, title='Impossible to delete upstream jobs. Please delete all associated downstream jobs first.']"
             )

      assert view |> render_click("delete_job", %{"id" => job.id}) =~
               "Unable to delete jobs with downstream jobs or runs."
    end

    test "project viewers can't delete jobs", %{
      conn: conn,
      project: project,
      job: job
    } do
      {conn, _user} = setup_project_user(conn, project, :viewer)

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
               "button[phx-click='delete_job'][title='You are not authorized to perform this action.'][disabled='disabled']"
             )

      assert view |> render_click("delete_job", %{"id" => job.id}) =~
               "You are not authorized to perform this action."

      assert_patch(
        view,
        Routes.project_workflow_path(conn, :show, project.id, job.workflow_id)
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

  describe "Show tooltip" do
    def tooltip_text(element) do
      element
      |> render()
      |> parse()
      |> xpath(~x"@aria-label"l)
      |> to_string()
    end

    test "should display tooltip", %{
      conn: conn,
      project: project
    } do
      workflow = workflow_fixture(name: "the workflow", project_id: project.id)

      {:ok, view, _html} =
        live(
          conn,
          Routes.project_workflow_path(conn, :new_job, project.id, workflow.id)
        )

      # Trigger tooltip
      assert view
             |> element("#trigger-tooltip")
             |> tooltip_text() ==
               "Choose when this job should run. Select 'webhook' for realtime workflows triggered by notifications from external systems."

      # Adaptor tooltip
      assert view
             |> element("#adaptor_name-tooltip")
             |> tooltip_text() ==
               "Choose an adaptor to perform operations (via helper functions) in a specific application. Pick ‘http’ for generic REST APIs or the 'common' adaptor if this job only performs data manipulation."

      # Credential tooltip
      assert view
             |> element("#project_credential_id-tooltip")
             |> tooltip_text() ==
               "If the system you're working with requires authentication, choose a credential with login details (secrets) that will allow this job to connect. If you're not connecting to an external system you don't need a credential."
    end
  end
end
