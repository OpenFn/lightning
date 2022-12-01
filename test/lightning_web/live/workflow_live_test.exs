defmodule LightningWeb.WorkflowLiveTest do
  use LightningWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import SweetXml

  setup :register_and_log_in_user
  setup :create_project_for_current_user

  import Lightning.JobsFixtures

  describe "show" do
    setup %{project: project} do
      %{job: job_fixture(project_id: project.id)}
    end

    test "renders the workflow diagram", %{
      conn: conn,
      project: project
    } do
      {:ok, view, html} =
        live(conn, Routes.project_workflow_path(conn, :show, project.id))

      assert html =~ project.name

      expected_encoded_project_space =
        Lightning.Workflows.get_workflows_for(project)
        |> Lightning.Workflows.to_project_space()
        |> Jason.encode!()
        |> Base.encode64()

      assert view
             |> element("div#hook-#{project.id}[phx-update=ignore]")
             |> render() =~ expected_encoded_project_space
    end
  end

  describe "edit_job" do
    setup %{project: project} do
      %{job: job_fixture(project_id: project.id)}
    end

    test "renders the job inspector", %{
      conn: conn,
      project: project,
      job: job
    } do
      {:ok, view, html} =
        live(
          conn,
          Routes.project_workflow_path(conn, :edit_job, project.id, job.id)
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

      # TODO: test that the compiler and editor get the new adaptor

      view |> element("#job-form") |> render_submit()

      assert_patch(view, Routes.project_workflow_path(conn, :show, project.id))

      assert render(view) =~ "Job updated successfully"

      view
      |> render_patch(
        Routes.project_workflow_path(conn, :edit_job, project.id, job.id)
      )

      assert has_element?(view, "#builder-#{job.id}")

      assert view |> has_expected_adaptor?("@openfn/language-http@latest")
    end
  end

  describe "new_job" do
    test "can be created with an upstream job", %{
      conn: conn,
      project: project
    } do
      upstream_job = job_fixture(project_id: project.id)

      {:ok, view, html} =
        live(
          conn,
          Routes.project_workflow_path(
            conn,
            :new_job,
            project.id,
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

      assert view
             |> has_option_text?("#adaptor-version", [
               'latest',
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
      |> form("#job-form", job_form: %{enabled: true, name: "My Job"})
      |> render_change()

      refute view |> has_error_for("name")

      view |> submit_form()

      assert_patch(view, Routes.project_workflow_path(conn, :show, project.id))

      assert view |> encoded_project_space_matches(project)
    end

    test "can be created without an upstream job", %{
      conn: conn,
      project: project
    } do
      {:ok, view, html} =
        live(
          conn,
          Routes.project_workflow_path(conn, :new_job, project.id)
        )

      assert html =~ project.name

      assert has_element?(view, "#job-form")

      view |> pick_adaptor_name("@openfn/language-common")

      view
      |> element("#job-editor-new")
      |> render_hook(:job_body_changed, %{source: "some body"})

      view
      |> form("#job-form", job_form: %{enabled: true, name: "My Job"})
      |> render_change()

      view |> submit_form()

      assert_patch(view, Routes.project_workflow_path(conn, :show, project.id))

      assert view |> encoded_project_space_matches(project)
    end
  end

  describe "edit_workflow" do
    setup %{project: project} do
      %{job: job_fixture(project_id: project.id)}
    end

    test "renders the workflow inspector", %{
      conn: conn,
      project: project,
      job: job
    } do
      {:ok, view, html} =
        live(
          conn,
          Routes.project_process_path(
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
        Routes.project_process_path(conn, :show, project.id, job.workflow_id)
      )

      assert view |> encoded_project_space_matches(project)
    end

    # TODO test that jobs in different projects are not available in flow triggers
    # TODO test that the current job is not visible in upstream jobs
  end

  defp has_expected_adaptor?(view, expected_adaptor) do
    view
    |> has_element?(
      ~s{#job-form select#adaptor-version option[selected=selected][value="#{expected_adaptor}"]}
    )
  end

  defp pick_adaptor_name(view, name) do
    view
    |> element("#adaptor-name")
    |> render_change(%{adaptor_picker: %{"adaptor_name" => name}})
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
      %{job: job_fixture(project_id: project.id)}
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
           project: project
         } do
      {:ok, view, html} =
        live(
          conn,
          Routes.project_workflow_path(conn, :new_job, project.id)
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
             |> form("#job-form", job_form: %{name: "my job", enabled: true})
             |> render_change()

      view |> submit_form() =~ "Job updated successfully"
      assert_patch(view, Routes.project_workflow_path(conn, :show, project.id))

      job =
        Lightning.Repo.get_by!(Lightning.Jobs.Job, %{name: "my job"})
        |> Lightning.Repo.preload([:workflow, :trigger])

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
          Routes.project_workflow_path(conn, :edit_job, project.id, job.id)
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
          Routes.project_workflow_path(conn, :edit_job, project.id, job.id)
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
          Routes.project_workflow_path(conn, :edit_job, project.id, job.id)
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
          Routes.project_workflow_path(conn, :edit_job, project.id, job.id)
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
          Routes.project_workflow_path(conn, :edit_job, project.id, job.id)
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
  defp encoded_project_space_matches(view, project) do
    view
    |> element("div#hook-#{project.id}[phx-update=ignore]")
    |> render()
    |> extract_project_space()
    |> Base.decode64!()
    |> Jason.decode!() ==
      Lightning.Workflows.get_workflows_for(project)
      |> Lightning.Workflows.to_project_space()
      |> Jason.encode!()
      |> Jason.decode!()
  end
end
