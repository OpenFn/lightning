defmodule LightningWeb.WorkflowLiveTest do
  use LightningWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import SweetXml

  setup :register_and_log_in_user
  setup :create_project_for_current_user

  import Lightning.JobsFixtures
  import Lightning.WorkflowsFixtures

  describe "index" do
    test "displays the current version", %{conn: conn, project: project} do
      {:ok, _view, html} =
        live(conn, Routes.project_workflow_path(conn, :index, project.id))

      assert html =~ "v#{elem(:application.get_key(:lightning, :vsn), 1)}"
    end

    test "lists all workflows for a project", %{
      conn: conn,
      project: project
    } do
      %{workflow: workflow_one} = workflow_job_fixture(project_id: project.id)
      %{workflow: workflow_two} = workflow_job_fixture(project_id: project.id)

      {:ok, view, html} =
        live(conn, Routes.project_workflow_path(conn, :index, project.id))

      assert html =~ "Create new workflow"

      assert view
             |> element(
               "li[phx-value-to='#{Routes.project_workflow_path(conn, :show, project.id, workflow_one.id)}']"
             )
             |> has_element?()

      assert view
             |> element(
               "li[phx-value-to='#{Routes.project_workflow_path(conn, :show, project.id, workflow_two.id)}']"
             )
             |> has_element?()
    end
  end

  describe "create" do
    test "Create empty workflow for a project", %{conn: conn, project: project} do
      {:ok, view, html} =
        live(conn, Routes.project_workflow_path(conn, :index, project.id))

      assert html =~ "Create new workflow"

      assert view
             |> element("li[role='button'][phx-click='create_workflow']")
             |> render_click() =~
               "Create job"
    end

    test "Project viewers can't create workflows", %{
      conn: conn,
      project: project
    } do
      {conn, _user} = setup_project_user(conn, project, :viewer)

      conn = get(conn, Routes.project_workflow_path(conn, :index, project.id))

      {:ok, view, html} =
        live(conn, Routes.project_workflow_path(conn, :index, project.id))

      assert html =~ "Create new workflow"

      assert view
             |> has_element?("li[phx-click='create_workflow']")

      refute view
             |> has_element?("li[role='button'][phx-click='create_workflow']")

      assert view
             |> render_click("create_workflow", %{}) =~
               "You are not authorized to perform this action."

      assert_patched(
        view,
        Routes.project_workflow_path(conn, :index, project.id)
      )
    end
  end

  describe "show" do
    test "renders prompt to create new job when workflow has no jobs", %{
      conn: conn,
      project: project
    } do
      workflow = workflow_fixture(name: "the workflow", project_id: project.id)

      {:ok, _view, html} =
        live(
          conn,
          ~p"/projects/#{project.id}/w/#{workflow.id}"
        )

      assert html =~ project.name
      assert html =~ "Create job"
    end

    test "renders the workflow diagram", %{
      conn: conn,
      project: project
    } do
      %{workflow: workflow} = workflow_job_fixture(project_id: project.id)

      {:ok, view, html} =
        live(
          conn,
          ~p"/projects/#{project.id}/w/#{workflow.id}"
        )

      assert html =~ project.name

      view |> encoded_project_space_matches(workflow)
    end
  end

  describe "copy webhook url" do
    test "click on webhook job node to copy webhook url to clipboard", %{
      conn: conn,
      project: project
    } do
      %{workflow: workflow} = workflow_job_fixture(project_id: project.id)

      {:ok, view, html} =
        live(
          conn,
          ~p"/projects/#{project.id}/w/#{workflow.id}"
        )

      assert html =~ project.name

      assert view |> render_click("copied_to_clipboard", %{}) =~
               "Copied webhook URL to clipboard"
    end
  end

  describe "edit_job" do
    setup %{project: project} do
      %{job: workflow_job_fixture(project_id: project.id)}
    end

    test "renders the job inspector", %{
      conn: conn,
      project: project,
      job: job
    } do
      {conn, _user} = setup_project_user(conn, project, :editor)

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

      assert has_element?(view, "#builder-#{job.id}")

      assert view
             |> form("#job-form", job_form: %{enabled: false, name: ""})
             |> render_change() =~ "can&#39;t be blank"

      view
      |> element("#job-form")
      |> render_change(job_form: %{enabled: true, name: "My Job"})

      refute view |> element("#job-form") |> render() =~ "can&#39;t be blank"

      view |> pick_adaptor_name("@openfn/language-http")

      assert view |> has_expected_version?("@openfn/language-http@latest")

      view |> pick_adaptor_version("@openfn/language-http@3.1.10")

      # TODO: test that the compiler and editor get the new adaptor

      view |> element("#job-form") |> render_submit()

      assert_patch(
        view,
        Routes.project_workflow_path(
          conn,
          :edit_job,
          project.id,
          job.workflow_id,
          job.id
        )
      )

      assert render(view) =~ "Job updated successfully"

      view
      |> render_patch(
        Routes.project_workflow_path(
          conn,
          :edit_job,
          project.id,
          job.workflow_id,
          job.id
        )
      )

      assert has_element?(view, "#builder-#{job.id}")

      assert view |> has_expected_version?("@openfn/language-http@3.1.10")
    end

    test "project viewers can't edit jobs", %{
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

      assert has_element?(view, "#builder-#{job.id}")

      assert has_element?(view, "input[id='job-form_name'][disabled='disabled']")

      assert has_element?(
               view,
               "input[name='job_form[enabled]'][disabled='disabled']"
             )

      assert has_element?(view, "select[id='triggerType'][disabled='disabled']")
      assert has_element?(view, "select[id='adaptor-name'][disabled='disabled']")

      assert has_element?(
               view,
               "select[id='adaptor-version'][disabled='disabled']"
             )

      assert has_element?(
               view,
               "select[id='credentialField'][disabled='disabled']"
             )

      assert has_element?(view, "button[type='submit'][disabled='disabled']")

      view |> element("#job-form") |> render_submit()

      assert_patch(
        view,
        Routes.project_workflow_path(conn, :show, project.id, job.workflow_id)
      )

      assert render(view) =~ " You are not authorized to perform this action."
    end
  end

  describe "new_job" do
    test "can be created with an upstream job", %{
      conn: conn,
      project: project
    } do
      {conn, _user} = setup_project_user(conn, project, :editor)

      upstream_job = workflow_job_fixture(project_id: project.id)

      {:ok, view, html} =
        live(
          conn,
          Routes.project_workflow_path(
            conn,
            :new_job,
            project.id,
            upstream_job.workflow_id,
            %{"upstream_id" => upstream_job.id}
          )
        )

      assert html =~ project.name

      assert has_element?(view, "#job-form")

      assert view
             |> element(
               ~S{#job-form select#upstream-job option[selected=selected]}
             )
             |> render() =~ upstream_job.id,
             "Should have the upstream job selected"

      view |> pick_adaptor_name("@openfn/language-common")

      view |> element("#adaptor-version") |> render()

      assert view
             |> has_option_text?("#adaptor-version", [
               'latest (≥ 1.6.2)',
               '2.14.0',
               '1.10.3',
               '1.2.22',
               '1.2.14',
               '1.2.3',
               '1.1.12',
               '1.1.0'
             ])

      assert view |> has_warning_on_editor_tab?()

      view
      |> element("#job-editor-new")
      |> render_hook(:job_body_changed, %{source: "some body"})

      refute view |> has_warning_on_editor_tab?()

      view |> submit_form()

      assert view |> has_error_for("name", "can't be blank")

      view
      |> form("#job-form", job_form: %{enabled: true, name: "New Job"})
      |> render_change()

      refute view |> has_error_for("name")

      view
      |> submit_form()

      job = Lightning.Repo.get_by!(Lightning.Jobs.Job, %{name: "New Job"})

      assert_patch(
        view,
        Routes.project_workflow_path(
          conn,
          :edit_job,
          project.id,
          job.workflow_id,
          job.id
        )
      )

      view |> encoded_project_space_matches(upstream_job.workflow)
    end

    test "can be created without an upstream job", %{
      conn: conn,
      project: project
    } do
      %{workflow: workflow} = workflow_job_fixture()

      {:ok, view, html} =
        live(
          conn,
          Routes.project_workflow_path(conn, :new_job, project.id, workflow.id)
        )

      assert html =~ project.name

      assert has_element?(view, "#job-form")

      view |> pick_adaptor_name("@openfn/language-common")

      view
      |> element("#job-editor-new")
      |> render_hook(:job_body_changed, %{source: "some body"})

      view
      |> form("#job-form", job_form: %{enabled: true, name: "DHIS2 Job"})
      |> render_change()

      view |> submit_form()

      job = Lightning.Repo.get_by!(Lightning.Jobs.Job, %{name: "DHIS2 Job"})

      assert_patch(
        view,
        Routes.project_workflow_path(
          conn,
          :edit_job,
          project.id,
          job.workflow_id,
          job.id
        )
      )

      view |> encoded_project_space_matches(workflow)
    end

    test "other project members can create a new job in a workflow", %{
      conn: conn,
      project: project
    } do
      workflow = workflow_fixture(name: "the workflow", project_id: project.id)

      {:ok, view, html} =
        live(
          conn,
          ~p"/projects/#{project.id}/w/#{workflow.id}"
        )

      assert html =~ project.name
      assert html =~ "Create job"

      assert view |> render_click("create_job", %{})

      assert_patched(
        view,
        ~p"/projects/#{project.id}/w/#{workflow.id}/j/new"
      )
    end

    test "project viewers can't create a new job in a workflow", %{
      conn: conn,
      project: project
    } do
      {conn, _user} = setup_project_user(conn, project, :viewer)

      workflow = workflow_fixture(name: "the workflow", project_id: project.id)

      {:ok, view, html} =
        live(
          conn,
          ~p"/projects/#{project.id}/w/#{workflow.id}"
        )

      assert html =~ project.name
      assert html =~ "Create job"

      assert view
             |> element("button[phx-click='create_job'][disabled]")
             |> has_element?()

      assert view |> render_click("create_job", %{}) =~
               "You are not authorized to perform this action."
    end
  end

  describe "edit_workflow" do
    setup %{project: project} do
      %{
        job:
          workflow_job_fixture(project_id: project.id, workflow_name: "Untitled")
      }
    end

    test "renders inplace workflow form", %{
      conn: conn,
      project: project,
      job: job
    } do
      {:ok, view, html} =
        live(
          conn,
          Routes.project_workflow_path(
            conn,
            :show,
            project.id,
            job.workflow_id
          )
        )

      assert html =~ project.name
      assert html =~ "Untitled"

      assert has_element?(view, "#workflow-#{job.workflow_id}")

      assert view
             |> form("#workflow-inplace-form", workflow: %{name: "my workflow"})
             |> render_change()

      assert view |> form("#workflow-inplace-form") |> render_submit() =~
               "my workflow"

      view
      |> encoded_project_space_matches(job.workflow |> Lightning.Repo.reload!())
    end

    test "renders the workflow inspector", %{
      conn: conn,
      project: project,
      job: job
    } do
      {:ok, view, html} =
        live(
          conn,
          Routes.project_workflow_path(
            conn,
            :edit_workflow,
            project.id,
            job.workflow_id
          )
        )

      assert html =~ project.name

      assert has_element?(view, "#workflow-#{job.workflow_id}")

      assert view
             |> form("#workflow-form", workflow: %{name: "my workflow"})
             |> render_change()

      view |> form("#workflow-form") |> render_submit()

      assert_patch(
        view,
        Routes.project_workflow_path(conn, :show, project.id, job.workflow_id)
      )

      view
      |> encoded_project_space_matches(job.workflow |> Lightning.Repo.reload!())
    end

    # TODO test that jobs in different projects are not available in flow triggers
    # TODO test that the current job is not visible in upstream jobs
  end

  describe "delete_workflow" do
    test "project viewer can't delete a workflow in that project",
         %{
           conn: conn,
           project: project
         } do
      workflow = workflow_fixture(name: "the workflow", project_id: project.id)
      {conn, _user} = setup_project_user(conn, project, :viewer)

      {:ok, view, _html} =
        live(conn, Routes.project_workflow_path(conn, :index, project.id))

      assert view
             |> render_click("delete_workflow", %{"id" => workflow.id}) =~
               "You are not authorized to perform this action."
    end

    test "delete a workflow on project index page",
         %{
           conn: conn,
           project: project
         } do
      workflow = workflow_fixture(name: "the workflow", project_id: project.id)

      {:ok, view, html} =
        live(conn, Routes.project_workflow_path(conn, :index, project.id))

      assert html =~ workflow.name

      assert view
             |> element("a[phx-click='delete_workflow']")
             |> render_click() =~
               "Workflow deleted successfully"

      refute has_element?(view, "workflow-#{workflow.id}")
    end

    test "delete a workflow on edit workflow page",
         %{
           conn: conn,
           project: project
         } do
      workflow = workflow_fixture(name: "the workflow", project_id: project.id)

      {:ok, view, html} =
        live(
          conn,
          Routes.project_workflow_path(
            conn,
            :edit_workflow,
            project.id,
            workflow.id
          )
        )

      assert html =~ workflow.name

      assert view
             |> element(
               "#workflow-#{workflow.id} a[phx-click='delete_workflow']"
             )
             |> render_click() =~
               "Workflow deleted successfully"

      refute has_element?(view, "workflow-#{workflow.id}")
    end
  end

  defp has_expected_version?(view, expected_version) do
    view
    |> has_element?(
      ~s{#job-form select#adaptor-version option[selected=selected][value="#{expected_version}"]}
    )
  end

  defp pick_adaptor_name(view, name) do
    view
    |> element("#adaptor-name")
    |> render_change(%{adaptor_picker: %{"adaptor_name" => name}})
  end

  defp pick_adaptor_version(view, version) do
    view
    |> form("#job-form", job_form: %{adaptor: version})
    |> render_change()
  end

  defp has_warning_on_editor_tab?(view) do
    view |> has_element?("#tab-item-editor > svg")
  end

  defp has_error_for(view, field, text_filter \\ nil) do
    view
    |> has_element?(
      ~s(#job-form [phx-feedback-for="job_form[#{field}]"]),
      text_filter
    )
  end

  defp submit_form(view) do
    view |> element("#job-form") |> render_submit()
  end

  describe "cron_setup_component" do
    alias LightningWeb.JobLive.CronSetupComponent

    setup %{project: project} do
      %{
        job:
          workflow_job_fixture(project_id: project.id, workflow_name: "Untitled")
      }
    end

    test "get_cron_data/1" do
      assert CronSetupComponent.get_cron_data("5 0 * 8 *")
             |> Map.get(:frequency) == "custom"

      assert CronSetupComponent.get_cron_data("5 0 8 * *") ==
               %{
                 :frequency => "monthly",
                 :minute => "05",
                 :hour => "00",
                 :monthday => "08"
               }

      assert CronSetupComponent.get_cron_data("5 0 * * 6") ==
               %{
                 :frequency => "weekly",
                 :minute => "05",
                 :hour => "00",
                 :weekday => "06"
               }

      assert CronSetupComponent.get_cron_data("50 0 * * *") ==
               %{
                 :frequency => "daily",
                 :minute => "50",
                 :hour => "00"
               }

      assert CronSetupComponent.get_cron_data("50 * * * *") ==
               %{
                 :frequency => "hourly",
                 :minute => "50"
               }

      assert CronSetupComponent.get_cron_data(nil) == %{}
    end

    test "build_cron_expression/2" do
      assert CronSetupComponent.build_cron_expression(
               "50 * * * *",
               %{
                 frequency: "hourly",
                 hour: "00",
                 minute: "34",
                 monthday: "01",
                 weekday: "01"
               }
             ) == "34 * * * *"

      assert CronSetupComponent.build_cron_expression(
               "50 * * * *",
               %{
                 frequency: "daily",
                 hour: "00",
                 minute: "34",
                 monthday: "01",
                 weekday: "01"
               }
             ) == "34 00 * * *"

      assert CronSetupComponent.build_cron_expression(
               "50 * * * *",
               %{
                 frequency: "weekly",
                 hour: "00",
                 minute: "34",
                 monthday: "01",
                 weekday: "01"
               }
             ) == "34 00 * * 01"

      assert CronSetupComponent.build_cron_expression(
               "50 * * * *",
               %{
                 frequency: "monthly",
                 hour: "00",
                 minute: "34",
                 monthday: "01",
                 weekday: "01"
               }
             ) == "34 00 01 * *"

      assert CronSetupComponent.build_cron_expression(
               "50 * * * *",
               %{
                 frequency: "custom",
                 hour: "00",
                 minute: "34",
                 monthday: "01",
                 weekday: "01"
               }
             ) == "50 * * * *"
    end

    test "cron_setup_component can create a new job with a default cron trigger",
         %{
           conn: conn,
           project: project,
           job: job
         } do
      {:ok, view, html} =
        live(
          conn,
          Routes.project_workflow_path(
            conn,
            :new_job,
            project.id,
            job.workflow_id
          )
        )

      assert html =~ project.name

      assert has_element?(view, "#job-form")

      assert view
             |> form("#job-form", job_form: %{trigger: %{type: "cron"}})
             |> render_change()

      assert view
             |> has_option_text?("#frequency", [
               'Every hour',
               'Every day',
               'Every week',
               'Every month',
               'Custom'
             ])

      view |> pick_adaptor_name("@openfn/language-common")

      view
      |> element("#job-editor-new")
      |> render_hook(:job_body_changed, %{source: "some body"})

      assert view
             |> form("#job-form", job_form: %{name: "timer job", enabled: true})
             |> render_change()

      view |> submit_form() =~ "Job created successfully"

      job =
        Lightning.Repo.get_by!(Lightning.Jobs.Job, %{name: "timer job"})
        |> Lightning.Repo.preload([:workflow, :trigger])

      assert_patch(
        view,
        Routes.project_workflow_path(
          conn,
          :edit_job,
          project.id,
          job.workflow_id,
          job.id
        )
      )

      due_for_execution =
        Timex.now()
        |> Timex.set(hour: 0, minute: 0, second: 0, microsecond: 0)
        |> Lightning.Jobs.get_jobs_for_cron_execution()

      assert job in due_for_execution
    end

    test "cron_setup_component can set trigger to a daily cron", %{
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

      assert job.trigger.type == :webhook

      assert html =~ project.name

      assert has_element?(view, "#job-form")

      assert view
             |> form("#job-form", job_form: %{trigger: %{type: "cron"}})
             |> render_change()

      assert view
             |> has_option_text?("#frequency", [
               'Every hour',
               'Every day',
               'Every week',
               'Every month',
               'Custom'
             ])

      assert view
             |> element("#frequency")
             |> render_change(%{cron_component: %{frequency: "daily"}})

      assert view |> element("#minute") |> render() =~ "00"

      assert view |> element("#hour") |> render() =~ "00"

      assert view
             |> element("#minute")
             |> render_change(%{cron_component: %{minute: "05"}})

      assert view
             |> element("#hour")
             |> render_change(%{cron_component: %{hour: "05"}})

      view |> submit_form() =~ "Job updated successfully"

      job = Lightning.Jobs.get_job!(job.id)

      assert job.trigger.type == :cron
      assert job.trigger.cron_expression == "05 05 * * *"
    end

    test "cron_setup_component can set trigger to an weekly cron", %{
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

      assert job.trigger.type == :webhook

      assert html =~ project.name

      assert has_element?(view, "#job-form")

      assert view
             |> form("#job-form", job_form: %{trigger: %{type: "cron"}})
             |> render_change()

      assert view
             |> has_option_text?("#frequency", [
               'Every hour',
               'Every day',
               'Every week',
               'Every month',
               'Custom'
             ])

      view |> change_cron(:frequency, "weekly")

      assert view |> element("#minute") |> render() =~ "00"
      assert view |> element("#hour") |> render() =~ "00"
      assert view |> element("#weekday") |> render() =~ "01"

      view |> change_cron(:minute, "05")
      view |> change_cron(:hour, "05")
      view |> change_cron(:weekday, "05")

      view |> submit_form() =~ "Job updated successfully"

      job = Lightning.Jobs.get_job!(job.id)

      assert job.trigger.type == :cron
      assert job.trigger.cron_expression == "05 05 * * 05"
    end

    test "cron_setup_component can set trigger to an monthly cron", %{
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

      assert job.trigger.type == :webhook

      assert html =~ project.name

      assert has_element?(view, "#job-form")

      assert view
             |> form("#job-form", job_form: %{trigger: %{type: "cron"}})
             |> render_change()

      assert view
             |> has_option_text?("#frequency", [
               'Every hour',
               'Every day',
               'Every week',
               'Every month',
               'Custom'
             ])

      assert view
             |> element("#frequency")
             |> render_change(%{cron_component: %{frequency: "monthly"}})

      assert view |> element("#minute") |> render() =~ "00"
      assert view |> element("#hour") |> render() =~ "00"
      assert view |> element("#monthday") |> render() =~ "01"

      assert view
             |> element("#minute")
             |> render_change(%{cron_component: %{minute: "05"}})

      assert view
             |> element("#hour")
             |> render_change(%{cron_component: %{hour: "05"}})

      assert view
             |> element("#monthday")
             |> render_change(%{cron_component: %{monthday: "05"}})

      view |> submit_form() =~ "Job updated successfully"

      job = Lightning.Jobs.get_job!(job.id)

      assert job.trigger.type == :cron
      assert job.trigger.cron_expression == "05 05 05 * *"
    end

    test "cron_setup_component can change from monthly to weekly", %{
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

      assert job.trigger.type == :webhook

      assert html =~ project.name

      assert has_element?(view, "#job-form")

      assert view
             |> form("#job-form", job_form: %{trigger: %{type: "cron"}})
             |> render_change()

      view |> change_cron(:frequency, "monthly")

      assert view |> has_element?("#minute", "00")
      assert view |> has_element?("#hour", "00")
      assert view |> has_element?("#monthday", "01")

      view |> change_cron(:minute, "10")
      view |> change_cron(:hour, "03")
      view |> change_cron(:monthday, "05")

      view |> submit_form() =~ "Job updated successfully"

      job = Lightning.Jobs.get_job!(job.id)

      assert job.trigger.type == :cron
      assert job.trigger.cron_expression == "10 03 05 * *"

      # For some reason LiveViewTest can't find the form components to trigger
      # `phx-change` on when entering the form again view a patch
      # view
      # |> render_patch(
      #   Routes.project_workflow_path(conn, :edit_job, project.id, job.id)
      # )

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

      assert view |> has_element?("#minute", "10")
      assert view |> has_element?("#hour", "03")
      assert view |> has_element?("#monthday", "05")

      view |> change_cron(:frequency, "weekly")

      view |> submit_form() =~ "Job updated successfully"

      job = Lightning.Jobs.get_job!(job.id)

      assert job.trigger.type == :cron
      assert job.trigger.cron_expression == "10 03 * * 01"
    end
  end

  defp has_option_text?(view, selector, opt_text) do
    view
    |> element(selector)
    |> render()
    |> parse()
    |> xpath(~x"option/text()"l) == opt_text
  end

  defp change_cron(view, field, value) do
    view
    |> element("##{field}")
    |> render_change(%{cron_component: %{field => value}})
  end

  defp extract_project_space(html) do
    [_, result] = Regex.run(~r/data-project-space="([[:alnum:]\=]+)"/, html)
    result
  end

  # Pull out the encoded ProjectSpace data from the html, turn it back into a
  # map and compare it to the current value.
  defp encoded_project_space_matches(view, workflow) do
    assert view
           |> element("div#hook-#{workflow.id}[phx-update=ignore]")
           |> render()
           |> extract_project_space() ==
             LightningWeb.WorkflowLive.encode_project_space(workflow)
  end
end
