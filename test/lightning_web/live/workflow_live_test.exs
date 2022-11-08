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

      assert has_element?(view, "##{job.id}")

      assert view
             |> form("#job-form", job_form: %{enabled: false, name: nil})
             |> render_change() =~ "can&#39;t be blank"
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

      assert_patch(view, Routes.project_workflow_path(conn, :show, project.id))

      assert view |> encoded_project_space_matches(project)
    end
  end

  describe "new_job" do
    setup %{project: project} do
      %{upstream_job: job_fixture(project_id: project.id)}
    end

    test "renders the workflow inspector", %{
      conn: conn,
      project: project,
      upstream_job: upstream_job
    } do
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
               ~S{#job-form select#upstreamJob option[selected=selected]}
             )
             |> render() =~ upstream_job.id,
             "Should have the upstream job selected"

      view
      |> element("#adaptorField")
      |> render_change(%{adaptor_name: "@openfn/language-common"})

      view
      |> element("#editor-component")
      |> render_hook(:job_body_changed, %{source: "some body"})

      assert view
             |> form("#job-form",
               job_form: %{
                 enabled: true,
                 name: "some name",
                 trigger_type: "on_job_failure"
               }
             )
             |> render_submit()

      assert_patch(view, Routes.project_workflow_path(conn, :show, project.id))

      assert view |> encoded_project_space_matches(project)
    end
  end

  describe "cron_setup_component" do
    setup %{project: project} do
      %{job: job_fixture(project_id: project.id)}
    end

    test "get_cron_data/1" do
      assert LightningWeb.JobLive.CronSetupComponent.get_cron_data("5 0 * 8 *")
             |> Map.get(:frequency) == "custom"

      assert LightningWeb.JobLive.CronSetupComponent.get_cron_data("5 0 8 * *") ==
               %{
                 :frequency => "monthly",
                 :minute => "05",
                 :hour => "00",
                 :monthday => "08"
               }

      assert LightningWeb.JobLive.CronSetupComponent.get_cron_data("5 0 * * 6") ==
               %{
                 :frequency => "weekly",
                 :minute => "05",
                 :hour => "00",
                 :weekday => "06"
               }

      assert LightningWeb.JobLive.CronSetupComponent.get_cron_data("50 0 * * *") ==
               %{
                 :frequency => "daily",
                 :minute => "50",
                 :hour => "00"
               }

      assert LightningWeb.JobLive.CronSetupComponent.get_cron_data("50 * * * *") ==
               %{
                 :frequency => "hourly",
                 :minute => "50"
               }

      assert LightningWeb.JobLive.CronSetupComponent.get_cron_data(nil) == %{}
    end

    test "get_cron_expression/2" do
      assert LightningWeb.JobLive.CronSetupComponent.get_cron_expression(
               %{
                 frequency: "hourly",
                 hour: "00",
                 minute: "34",
                 monthday: "01",
                 weekday: "01"
               },
               "50 * * * *"
             ) == "34 * * * *"

      assert LightningWeb.JobLive.CronSetupComponent.get_cron_expression(
               %{
                 frequency: "daily",
                 hour: "00",
                 minute: "34",
                 monthday: "01",
                 weekday: "01"
               },
               "50 * * * *"
             ) == "34 00 * * *"

      assert LightningWeb.JobLive.CronSetupComponent.get_cron_expression(
               %{
                 frequency: "weekly",
                 hour: "00",
                 minute: "34",
                 monthday: "01",
                 weekday: "01"
               },
               "50 * * * *"
             ) == "34 00 * * 01"

      assert LightningWeb.JobLive.CronSetupComponent.get_cron_expression(
               %{
                 frequency: "monthly",
                 hour: "00",
                 minute: "34",
                 monthday: "01",
                 weekday: "01"
               },
               "50 * * * *"
             ) == "34 00 01 * *"

      assert LightningWeb.JobLive.CronSetupComponent.get_cron_expression(
               %{
                 frequency: "custom",
                 hour: "00",
                 minute: "34",
                 monthday: "01",
                 weekday: "01"
               },
               "50 * * * *"
             ) == "50 * * * *"
    end

    test "cron_setup_component can set trigger to an hourly cron", %{
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
             |> form("#job-form",
               job_form: %{trigger_type: "cron"}
             )
             |> render_change()

      assert view
             |> element("#frequency")
             |> render()
             |> parse()
             |> xpath(~x"option/text()"l) == [
               'Every hour',
               'Every day',
               'Every week',
               'Every month',
               'Custom'
             ]

      assert view
             |> element("#frequency")
             |> render_change(%{cron_component: %{frequency: "hourly"}})

      assert view |> element("#minute") |> render() =~ "00"

      assert view
             |> element("#minute")
             |> render_change(%{cron_component: %{minute: "05"}})

      view |> form("#job-form") |> render_submit() =~ "Job updated successfully"

      job = Lightning.Jobs.get_job!(job.id)

      assert job.trigger.type == :cron
      assert job.trigger.cron_expression == "05 * * * *"

      # view |> form("#job-form") |> render_submit()

      # assert_patch(view, Routes.project_workflow_path(conn, :show, project.id))

      # view
      # |> render_patch(
      #   Routes.project_workflow_path(conn, :edit_job, project.id, job.id)
      # )

      # assert view
      #        |> has_element?("#frequency option[selected][value=monthly]"),
      #        "Should have the option that was previously selected"
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
            job.id
          )
        )

      assert job.trigger.type == :webhook

      assert html =~ project.name

      assert has_element?(view, "#job-form")

      assert view
             |> form("#job-form",
               job_form: %{trigger_type: "cron"}
             )
             |> render_change()

      assert view
             |> element("#frequency")
             |> render()
             |> parse()
             |> xpath(~x"option/text()"l) == [
               'Every hour',
               'Every day',
               'Every week',
               'Every month',
               'Custom'
             ]

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

      view |> form("#job-form") |> render_submit() =~ "Job updated successfully"

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
            job.id
          )
        )

      assert job.trigger.type == :webhook

      assert html =~ project.name

      assert has_element?(view, "#job-form")

      assert view
             |> form("#job-form",
               job_form: %{trigger_type: "cron"}
             )
             |> render_change()

      assert view
             |> element("#frequency")
             |> render()
             |> parse()
             |> xpath(~x"option/text()"l) == [
               'Every hour',
               'Every day',
               'Every week',
               'Every month',
               'Custom'
             ]

      assert view
             |> element("#frequency")
             |> render_change(%{cron_component: %{frequency: "weekly"}})

      assert view |> element("#minute") |> render() =~ "00"
      assert view |> element("#hour") |> render() =~ "00"
      assert view |> element("#weekday") |> render() =~ "01"

      assert view
             |> element("#minute")
             |> render_change(%{cron_component: %{minute: "05"}})

      assert view
             |> element("#hour")
             |> render_change(%{cron_component: %{hour: "05"}})

      assert view
             |> element("#weekday")
             |> render_change(%{cron_component: %{weekday: "05"}})

      view |> form("#job-form") |> render_submit() =~ "Job updated successfully"

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
            job.id
          )
        )

      assert job.trigger.type == :webhook

      assert html =~ project.name

      assert has_element?(view, "#job-form")

      assert view
             |> form("#job-form",
               job_form: %{trigger_type: "cron"}
             )
             |> render_change()

      assert view
             |> element("#frequency")
             |> render()
             |> parse()
             |> xpath(~x"option/text()"l) == [
               'Every hour',
               'Every day',
               'Every week',
               'Every month',
               'Custom'
             ]

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

      view |> form("#job-form") |> render_submit() =~ "Job updated successfully"

      job = Lightning.Jobs.get_job!(job.id)

      assert job.trigger.type == :cron
      assert job.trigger.cron_expression == "05 05 05 * *"
    end
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
