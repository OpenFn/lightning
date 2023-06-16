defmodule LightningWeb.WorkflowNewLiveTest do
  use LightningWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Lightning.JobsFixtures

  import SweetXml

  alias LightningWeb.JobLive.CronSetupComponent

  setup :register_and_log_in_user
  setup :create_project_for_current_user

  describe "new" do
    test "builds a new workflow", %{conn: conn, project: project} do
      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/w-new/new")

      # Naively add a job via the editor (calling the push-change event)
      assert view
             |> element("#editor-#{project.id}")
             |> push_patches_to_view([add_job_patch()])

      # The server responds with a patch with any further changes
      assert_reply(
        view,
        %{
          patches: [
            %{
              op: "add",
              path: "/jobs/0/errors",
              value: %{
                "body" => ["can't be blank"],
                "name" => ["can't be blank"]
              }
            },
            %{op: "add", path: "/jobs/0/enabled", value: "true"},
            %{op: "add", path: "/jobs/0/body", value: ""},
            %{
              op: "add",
              path: "/jobs/0/adaptor",
              value: "@openfn/language-common@latest"
            }
          ]
        }
      )
    end
  end

  defp push_patches_to_view(elem, patches) do
    elem
    |> render_hook("push-change", %{patches: patches})
  end

  defp add_job_patch(name \\ "") do
    Jsonpatch.diff(
      %{jobs: []},
      %{jobs: [%{id: Ecto.UUID.generate(), name: name}]}
    )
    |> Jsonpatch.Mapper.to_map()
    |> List.first()
    |> Lightning.Helpers.json_safe()
  end

  describe "cron_setup_component" do
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
      {:ok, view, html} = live(conn, ~p"/project/#{p.id}/w-new/new/j/#{job.id}")

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

  defp pick_adaptor_name(view, name) do
    view
    |> element("#adaptor-name")
    |> render_change(%{adaptor_picker: %{"adaptor_name" => name}})
  end

  defp submit_form(view) do
    view |> element("#job-form") |> render_submit()
  end
end
