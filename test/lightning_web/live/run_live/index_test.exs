defmodule LightningWeb.RunLive.IndexTest do
  use LightningWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Lightning.Factories

  alias Lightning.WorkOrders
  alias Lightning.WorkOrders.SearchParams

  setup :register_and_log_in_superuser
  setup :create_project_for_current_user
  setup :stub_usage_limiter_ok

  setup %{project: project} do
    %{project: project, triggers: [trigger], jobs: jobs} =
      workflow = insert(:complex_workflow, project: project) |> with_snapshot()

    dataclip = insert(:dataclip, project: project)

    work_order_1 =
      insert(:workorder,
        workflow: workflow,
        trigger: trigger,
        dataclip: dataclip,
        last_activity: DateTime.utc_now()
      )
      |> with_run(
        state: :failed,
        dataclip: dataclip,
        starting_trigger: trigger,
        finished_at: build(:timestamp),
        steps:
          jobs
          |> Enum.map(fn j ->
            build(:step,
              job: j,
              input_dataclip: dataclip,
              started_at: build(:timestamp),
              finished_at: build(:timestamp),
              exit_reason: "failed"
            )
          end)
      )

    dataclip = insert(:dataclip, project: project)

    work_order_2 =
      insert(:workorder,
        workflow: workflow,
        trigger: trigger,
        dataclip: dataclip,
        last_activity: DateTime.utc_now()
      )
      |> with_run(
        state: :failed,
        dataclip: dataclip,
        starting_trigger: trigger,
        finished_at: build(:timestamp),
        steps:
          jobs
          |> Enum.map(fn j ->
            build(:step,
              job: j,
              input_dataclip: dataclip,
              started_at: build(:timestamp),
              finished_at: build(:timestamp),
              exit_reason: "failed"
            )
          end)
      )

    %{
      work_order_1: work_order_1,
      work_order_2: work_order_2,
      jobs: jobs,
      workflow: workflow,
      selected_workorders: [work_order_1, work_order_2]
    }
  end

  describe "bulk rerun from job" do
    @tag role: :editor
    test "only selecting workorders from the same workflow shows the rerun button",
         %{conn: conn, project: project} do
      trigger = build(:trigger, type: :webhook)

      job_a =
        build(:job,
          body: ~s[fn(state => { return {...state, extra: "data"} })],
          name: "First Job"
        )

      workflow =
        build(:workflow, project: project)
        |> with_job(job_a)
        |> with_trigger(trigger)
        |> with_edge({trigger, job_a})
        |> insert()

      job_a = job_a |> Lightning.Repo.reload()
      trigger = trigger |> Lightning.Repo.reload()

      dataclip = insert(:dataclip, project: project)

      work_order_3 =
        insert(:workorder,
          workflow: workflow,
          trigger: trigger,
          dataclip: dataclip,
          state: :success,
          last_activity: DateTime.utc_now()
        )
        |> with_run(
          starting_trigger: trigger,
          dataclip: dataclip,
          finished_at: build(:timestamp),
          steps: [
            %{
              job: job_a,
              started_at: build(:timestamp),
              finished_at: build(:timestamp),
              exit_reason: "success",
              input_dataclip: dataclip
            }
          ]
        )

      {:ok, view, html} =
        live_async(
          conn,
          Routes.project_run_index_path(conn, :index, project.id,
            filters: %{
              body: true,
              log: true,
              success: true,
              pending: true,
              crashed: true,
              failed: true,
              killed: true,
              running: true
            }
          )
        )

      refute html =~ "Retry from"

      # All work orders have been selected
      refute render_change(view, "toggle_all_selections", %{
               all_selections: true
             }) =~ "Retry from"

      # uncheck 1 work order
      view
      |> form("#selection-form-#{work_order_3.id}")
      |> render_change(%{selected: false})

      assert render_async(view) =~ "Retry from"
    end

    @tag role: :viewer
    test "Project viewers can't rerun runs", %{
      conn: conn,
      project: project,
      jobs: [job_a | _rest]
    } do
      {:ok, view, _html} =
        live(
          conn,
          Routes.project_run_index_path(conn, :index, project.id,
            filters: %{
              body: true,
              log: true,
              success: true,
              pending: true,
              crash: true,
              failure: true
            }
          )
        )

      render_change(view, "toggle_all_selections", %{all_selections: true})

      assert render_click(view, "bulk-rerun", %{type: "all", job: job_a.id}) =~
               "You are not authorized to perform this action."
    end

    @tag role: :editor
    test "Project editors can rerun runs", %{
      conn: conn,
      project: project,
      jobs: [job_a | _rest],
      work_order_1: work_order_1
    } do
      path =
        Routes.project_run_index_path(conn, :index, project.id,
          filters: %{
            body: true,
            log: true,
            success: true,
            pending: true,
            crash: true,
            failure: true
          }
        )

      {:ok, view, html} = live(conn, path)

      render_async(view)

      refute html =~
               "Find all runs that include this step and rerun from there"

      assert render_change(view, "toggle_all_selections", %{
               all_selections: true
             }) =~ "Find all runs that include this step and rerun from there"

      view
      |> form("#select-job-for-rerun-form")
      |> render_change(%{job: job_a.id})

      result = view |> render_click("bulk-rerun", %{type: "all", job: job_a.id})

      {:ok, view, html} = follow_redirect(result, conn)

      assert html =~
               "New runs enqueued for 2 workorders"

      render_async(view)

      view
      |> form("#selection-form-#{work_order_1.id}")
      |> render_change(%{selected: true})

      view
      |> form("#select-job-for-rerun-form")
      |> render_change(%{job: job_a.id})

      result =
        view |> element("#rerun-selected-from-job-trigger") |> render_click()

      {:ok, _view, html} = follow_redirect(result, conn)

      # this is zero because the previous retried run has no steps
      assert html =~ "New run enqueued for 0 workorder"
    end

    test "jobs on the modal are updated every time the selected workflow is changed",
         %{
           conn: conn,
           project: project
         } do
      scenarios =
        Enum.map(1..3, fn _n ->
          %{triggers: [trigger], jobs: jobs} =
            workflow = insert(:complex_workflow, project: project)

          dataclip = insert(:dataclip, project: project)

          work_order =
            insert(:workorder,
              state: :success,
              workflow: workflow,
              trigger: trigger,
              dataclip: dataclip,
              last_activity: DateTime.utc_now()
            )
            |> with_run(
              state: :success,
              dataclip: dataclip,
              starting_trigger: trigger,
              started_at: build(:timestamp),
              finished_at: build(:timestamp),
              steps:
                Enum.map(jobs, fn j ->
                  build(:step,
                    job: j,
                    input_dataclip: dataclip,
                    output_dataclip: dataclip,
                    started_at: build(:timestamp),
                    finished_at: build(:timestamp),
                    exit_reason: "success"
                  )
                end)
            )

          %{work_order: work_order, workflow: workflow, jobs: jobs}
        end)

      path =
        Routes.project_run_index_path(conn, :index, project.id,
          filters: %{
            body: true,
            log: true,
            success: true,
            pending: true,
            killed: true,
            running: true,
            crashed: true,
            failed: true
          }
        )

      {:ok, view, _html} = live_async(conn, path)

      for scenario <- scenarios do
        for job <- scenario.jobs do
          refute has_element?(view, "input#job_#{job.id}")
        end

        view
        |> form("#selection-form-#{scenario.work_order.id}")
        |> render_change(%{selected: true})

        for job <- scenario.jobs do
          assert has_element?(view, "input#job_#{job.id}")
        end

        view
        |> form("#selection-form-#{scenario.work_order.id}")
        |> render_change(%{selected: false})
      end
    end

    test "all jobs in the selected workflow are displayed", %{
      workflow: workflow,
      selected_workorders: selected_workorders,
      jobs: jobs
    } do
      html =
        render_component(
          LightningWeb.RunLive.RerunJobComponent,
          id: "bulk-rerun-from-start-modal",
          total_entries: 25,
          all_selected?: true,
          selected_workorders: selected_workorders,
          pages: 2,
          filters: %SearchParams{},
          workflow_id: workflow.id
        )

      for job <- jobs do
        assert html =~ job.name
      end
    end

    test "a job with a latest step having wiped dataclip is shown disabled", %{
      workflow: workflow,
      work_order_1: work_order_1,
      jobs: jobs
    } do
      # disabled job
      last_job = List.last(jobs)
      second_last_job = jobs |> List.delete(last_job) |> List.last()

      # get latest run step
      [%{step: step_last_job}] =
        WorkOrders.get_last_runs_steps_with_dataclips([work_order_1], [last_job])

      [%{step: step_second_last_job}] =
        WorkOrders.get_last_runs_steps_with_dataclips([work_order_1], [
          second_last_job
        ])

      # these 2 last jobs have steps with a wipe dataclip
      wiped_dataclip = insert(:dataclip, wiped_at: Timex.now())

      step_last_job
      |> Ecto.Changeset.change(%{input_dataclip_id: wiped_dataclip.id})
      |> Repo.update!()

      step_second_last_job
      |> Ecto.Changeset.change(%{input_dataclip_id: wiped_dataclip.id})
      |> Repo.update!()

      html =
        render_component(
          LightningWeb.RunLive.RerunJobComponent,
          id: "bulk-rerun-from-start-modal",
          total_entries: 25,
          all_selected?: true,
          selected_workorders: [work_order_1],
          pages: 2,
          filters: %SearchParams{},
          workflow_id: workflow.id
        )

      Enum.each(jobs, fn job ->
        label =
          html
          |> Floki.parse_fragment!()
          |> Floki.find("#jobl_#{job.id}")
          |> Floki.attribute("class")
          |> List.first()

        disabled =
          html
          |> Floki.parse_fragment!()
          |> Floki.find("#job_#{job.id}")
          |> Floki.attribute("disabled")
          |> List.first()

        if job.id in [last_job.id, second_last_job.id] do
          assert disabled
          assert label =~ "text-slate-500"
        else
          refute disabled
          assert label =~ "text-gray-900"
        end
      end)
    end

    test "2 run buttons are present when all entries have been selected", %{
      workflow: workflow,
      selected_workorders: selected_workorders
    } do
      html =
        render_component(
          LightningWeb.RunLive.RerunJobComponent,
          id: "bulk-rerun-from-start-modal",
          total_entries: 25,
          all_selected?: true,
          selected_workorders: selected_workorders,
          pages: 2,
          filters: %SearchParams{},
          workflow_id: workflow.id
        )

      assert html =~ "Rerun all 25 matching work orders from selected job"

      assert html =~
               "Rerun #{length(selected_workorders)} selected work orders from selected job"
    end

    test "only 1 run button is present when some entries have been selected", %{
      workflow: workflow,
      selected_workorders: selected_workorders
    } do
      html =
        render_component(
          LightningWeb.RunLive.RerunJobComponent,
          id: "bulk-rerun-from-start-modal",
          total_entries: 25,
          all_selected?: false,
          selected_workorders: selected_workorders,
          pages: 2,
          filters: %SearchParams{},
          workflow_id: workflow.id
        )

      refute html =~ "Rerun all 25 matching work orders from selected job"

      assert html =~
               "Rerun #{length(selected_workorders)} selected work orders from selected job"
    end

    test "only 1 run button is present when total pages is 1", %{
      workflow: workflow,
      selected_workorders: selected_workorders
    } do
      html =
        render_component(
          LightningWeb.RunLive.RerunJobComponent,
          id: "bulk-rerun-from-start-modal",
          total_entries: 25,
          all_selected?: true,
          selected_workorders: selected_workorders,
          pages: 1,
          filters: %SearchParams{},
          workflow_id: workflow.id
        )

      refute html =~ "Rerun all 25 matching work orders from selected job"

      assert html =~
               "Rerun #{length(selected_workorders)} selected work orders from selected job"
    end
  end
end
