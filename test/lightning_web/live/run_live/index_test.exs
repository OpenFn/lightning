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

    snapshot = Lightning.Workflows.Snapshot.get_current_for(workflow)

    dataclip = insert(:dataclip, project: project)

    work_order_1 =
      insert(:workorder,
        workflow: workflow,
        trigger: trigger,
        dataclip: dataclip,
        state: :failed,
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
              snapshot: snapshot,
              input_dataclip: dataclip,
              started_at: build(:timestamp),
              finished_at: build(:timestamp),
              exit_reason: "fail"
            )
          end)
      )

    dataclip = insert(:dataclip, project: project)

    work_order_2 =
      insert(:workorder,
        workflow: workflow,
        trigger: trigger,
        dataclip: dataclip,
        state: :failed,
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
              snapshot: snapshot,
              input_dataclip: dataclip,
              started_at: build(:timestamp),
              finished_at: build(:timestamp),
              exit_reason: "fail"
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
              crashed: true,
              failed: true
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
            crashed: true,
            failed: true
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

  describe "channel logs tab" do
    test "tab bar is hidden when experimental features are disabled", %{
      conn: conn,
      project: project
    } do
      {:ok, _view, html} =
        live_async(
          conn,
          Routes.project_run_index_path(conn, :index, project.id)
        )

      refute html =~ "Channel Logs"
      refute html =~ "Work Orders</a>"
    end

    test "tab bar is visible when experimental features are enabled", %{
      conn: conn,
      project: project,
      user: user
    } do
      Lightning.Accounts.update_user_preferences(user, %{
        "experimental_features" => true
      })

      {:ok, _view, html} =
        live_async(
          conn,
          Routes.project_run_index_path(conn, :index, project.id)
        )

      assert html =~ "Channel Logs"
      assert html =~ "Work Orders"
    end

    test "navigating to channel logs tab renders channel logs content", %{
      conn: conn,
      project: project,
      user: user
    } do
      Lightning.Accounts.update_user_preferences(user, %{
        "experimental_features" => true
      })

      {:ok, view, _html} =
        live(conn, ~p"/projects/#{project.id}/history/channels")

      html = render(view)
      assert html =~ "Channel is"
      assert html =~ "channel_filter_dropdown"
    end

    test "channel logs tab shows empty state with no requests", %{
      conn: conn,
      project: project,
      user: user
    } do
      Lightning.Accounts.update_user_preferences(user, %{
        "experimental_features" => true
      })

      {:ok, _view, html} =
        live(conn, ~p"/projects/#{project.id}/history/channels")

      assert html =~ "No channel requests found."
    end

    test "channel logs tab renders channel request rows", %{
      conn: conn,
      project: project,
      user: user
    } do
      Lightning.Accounts.update_user_preferences(user, %{
        "experimental_features" => true
      })

      channel = insert(:channel, project: project, name: "test-channel")

      {:ok, snapshot} =
        Lightning.Channels.get_or_create_current_snapshot(channel)

      insert(:channel_request,
        channel: channel,
        channel_snapshot: snapshot,
        state: :success,
        started_at: DateTime.utc_now()
      )

      {:ok, _view, html} =
        live(conn, ~p"/projects/#{project.id}/history/channels")

      assert html =~ "test-channel"
    end

    test "channel filter works within history page", %{
      conn: conn,
      project: project,
      user: user
    } do
      Lightning.Accounts.update_user_preferences(user, %{
        "experimental_features" => true
      })

      ch1 = insert(:channel, project: project, name: "channel-one")
      ch2 = insert(:channel, project: project, name: "channel-two")

      {:ok, snap1} =
        Lightning.Channels.get_or_create_current_snapshot(ch1)

      {:ok, snap2} =
        Lightning.Channels.get_or_create_current_snapshot(ch2)

      cr1 =
        insert(:channel_request,
          channel: ch1,
          channel_snapshot: snap1,
          state: :success,
          started_at: DateTime.utc_now()
        )

      cr2 =
        insert(:channel_request,
          channel: ch2,
          channel_snapshot: snap2,
          state: :success,
          started_at: DateTime.utc_now()
        )

      {:ok, _view, html} =
        live(
          conn,
          ~p"/projects/#{project.id}/history/channels?#{%{filters: %{channel_id: ch1.id}}}"
        )

      assert html =~ cr1.request_id
      refute html =~ cr2.request_id
    end

    test "work orders content is hidden on channel logs tab", %{
      conn: conn,
      project: project,
      user: user
    } do
      Lightning.Accounts.update_user_preferences(user, %{
        "experimental_features" => true
      })

      {:ok, _view, html} =
        live(conn, ~p"/projects/#{project.id}/history/channels")

      refute html =~ "workorder-filter-form"
    end

    test "old /channels/requests route no longer works", %{
      conn: conn,
      project: project
    } do
      assert_raise FunctionClauseError, fn ->
        live(conn, "/projects/#{project.id}/channels/requests")
      end
    end
  end

  describe "filter chips" do
    test "workflow filter chip shows active state when workflow selected", %{
      conn: conn,
      project: project,
      workflow: workflow
    } do
      {:ok, view, _html} =
        live_async(
          conn,
          Routes.project_run_index_path(conn, :index, project.id)
        )

      # Initially shows "Workflow is any"
      chip = element(view, "#workflow-filter-chip")
      assert render(chip) =~ "Workflow is"
      assert render(chip) =~ "any"

      # Select a workflow via the apply_filters event
      view
      |> render_hook("apply_filters", %{
        "filters" => %{"workflow_id" => workflow.id}
      })

      # Chip now shows the workflow name and the clear button
      html = render(view)
      assert html =~ workflow.name
      assert has_element?(view, "[aria-label=\"Clear filter\"]")
    end

    test "clearing workflow filter resets chip to inactive", %{
      conn: conn,
      project: project,
      workflow: workflow
    } do
      {:ok, view, _html} =
        live_async(
          conn,
          Routes.project_run_index_path(conn, :index, project.id,
            filters: %{workflow_id: workflow.id}
          )
        )

      # Workflow is active
      html = render(view)
      assert html =~ workflow.name

      # Clear the filter
      view
      |> render_hook("apply_filters", %{
        "filters" => %{"workflow_id" => ""}
      })

      html = render(view)
      assert html =~ "Workflow is"
      assert html =~ "any"
    end

    test "status filter chip shows selected statuses", %{
      conn: conn,
      project: project
    } do
      {:ok, view, _html} =
        live_async(
          conn,
          Routes.project_run_index_path(conn, :index, project.id)
        )

      # Initially shows "Status is any"
      chip = element(view, "#status-filter-chip")
      assert render(chip) =~ "Status"
      assert render(chip) =~ "any"

      # Select a status via apply_filters
      view
      |> render_hook("apply_filters", %{
        "filters" => %{"failed" => "true"}
      })

      html = render(view)
      assert html =~ "Failed"
    end

    test "status filter chip shows 'in' for multiple statuses", %{
      conn: conn,
      project: project
    } do
      {:ok, view, _html} =
        live_async(
          conn,
          Routes.project_run_index_path(conn, :index, project.id,
            filters: %{failed: true, success: true}
          )
        )

      html = render(view)
      assert html =~ "Status in"
      assert html =~ "Failed"
      assert html =~ "Success"
    end

    test "date filter chips show date range when active", %{
      conn: conn,
      project: project
    } do
      {:ok, view, _html} =
        live_async(
          conn,
          Routes.project_run_index_path(conn, :index, project.id,
            filters: %{wo_date_after: "2025-01-01T00:00"}
          )
        )

      chip = element(view, "#received-filter-chip")
      html = render(chip)
      assert html =~ "Received"
      assert html =~ "after"
    end

    test "clearing date filter resets chip", %{
      conn: conn,
      project: project
    } do
      {:ok, view, _html} =
        live_async(
          conn,
          Routes.project_run_index_path(conn, :index, project.id,
            filters: %{wo_date_after: "2025-01-01T00:00"}
          )
        )

      # Clear the received date filter
      view
      |> render_hook("apply_filters", %{
        "filters" => %{"wo_date_after" => "", "wo_date_before" => ""}
      })

      chip = element(view, "#received-filter-chip")
      html = render(chip)
      assert html =~ "any time"
    end

    test "workorder ID chip appears when workorder_id filter is set", %{
      conn: conn,
      project: project,
      work_order_1: wo
    } do
      {:ok, view, _html} =
        live_async(
          conn,
          Routes.project_run_index_path(conn, :index, project.id,
            filters: %{
              workorder_id: wo.id,
              failed: true
            }
          )
        )

      assert has_element?(view, "#workorder-id-filter-chip")
      chip = element(view, "#workorder-id-filter-chip")
      assert render(chip) =~ "Work order:"
    end
  end

  describe "cancel work orders" do
    @tag role: :editor
    test "cancel button shown for pending WOs, retry for final states",
         %{
           conn: conn,
           project: project,
           workflow: workflow,
           work_order_1: failed_wo
         } do
      trigger = List.first(workflow.triggers)
      dataclip = insert(:dataclip, project: project)

      pending_wo =
        insert(:workorder,
          workflow: workflow,
          trigger: trigger,
          dataclip: dataclip,
          state: :pending,
          last_activity: DateTime.utc_now()
        )
        |> with_run(
          state: :available,
          dataclip: dataclip,
          starting_trigger: trigger
        )

      {:ok, view, _html} =
        live_async(
          conn,
          Routes.project_run_index_path(conn, :index, project.id,
            filters: %{pending: true, failed: true}
          )
        )

      # Pending WO shows cancel button, not retry
      assert has_element?(view, "button#cancel-wo-#{pending_wo.id}")
      refute has_element?(view, "button#retry-workorder-#{pending_wo.id}")

      # Failed WO shows retry button, not cancel
      assert has_element?(view, "button#retry-workorder-#{failed_wo.id}")
      refute has_element?(view, "button#cancel-wo-#{failed_wo.id}")
    end

    @tag role: :editor
    test "bulk cancel for selected pending work orders",
         %{conn: conn, project: project, workflow: workflow} do
      trigger = List.first(workflow.triggers)
      dataclip = insert(:dataclip, project: project)

      pending_wo =
        insert(:workorder,
          workflow: workflow,
          trigger: trigger,
          dataclip: dataclip,
          state: :pending,
          last_activity: DateTime.utc_now()
        )
        |> with_run(
          state: :available,
          dataclip: dataclip,
          starting_trigger: trigger
        )

      {:ok, view, _html} =
        live_async(
          conn,
          Routes.project_run_index_path(conn, :index, project.id,
            filters: %{pending: true}
          )
        )

      # Select the pending work order
      view
      |> form("#selection-form-#{pending_wo.id}")
      |> render_change(%{selected: true})

      # Cancel button should be enabled in toolbar
      assert has_element?(view, "button#bulk-cancel-modal-trigger")
      # Retry should be disabled
      refute has_element?(view, "button#bulk-rerun-from-start-job-modal-trigger")

      # Click bulk cancel
      result = render_click(view, "bulk-cancel", %{type: "selected"})
      {:ok, _view, html} = follow_redirect(result, conn)

      assert html =~ "Cancelled 1 run"
    end

    @tag role: :editor
    test "single work order cancel from inline button",
         %{conn: conn, project: project, workflow: workflow} do
      trigger = List.first(workflow.triggers)
      dataclip = insert(:dataclip, project: project)

      pending_wo =
        insert(:workorder,
          workflow: workflow,
          trigger: trigger,
          dataclip: dataclip,
          state: :pending,
          last_activity: DateTime.utc_now()
        )
        |> with_run(
          state: :available,
          dataclip: dataclip,
          starting_trigger: trigger
        )

      {:ok, view, _html} =
        live_async(
          conn,
          Routes.project_run_index_path(conn, :index, project.id,
            filters: %{pending: true}
          )
        )

      html =
        render_click(view, "cancel", %{
          "workorder_id" => pending_wo.id
        })

      assert html =~ "Work order cancelled."
    end

    @tag role: :editor
    test "per-run cancel button in expanded run rows",
         %{conn: conn, project: project, workflow: workflow} do
      trigger = List.first(workflow.triggers)
      dataclip = insert(:dataclip, project: project)

      pending_wo =
        insert(:workorder,
          workflow: workflow,
          trigger: trigger,
          dataclip: dataclip,
          state: :pending,
          last_activity: DateTime.utc_now()
        )
        |> with_run(
          state: :available,
          dataclip: dataclip,
          starting_trigger: trigger
        )

      run = List.first(pending_wo.runs)

      {:ok, view, _html} =
        live_async(
          conn,
          Routes.project_run_index_path(conn, :index, project.id,
            filters: %{pending: true}
          )
        )

      # Expand work order details
      view
      |> element("#toggle_details_for_#{pending_wo.id}")
      |> render_click()

      # Cancel button should be visible for the available run
      assert has_element?(view, "button#cancel-run-#{run.id}")

      # Cancel the run
      html =
        render_click(view, "cancel-run", %{"run_id" => run.id})

      assert html =~ "Run cancelled."
    end

    @tag role: :viewer
    test "viewers cannot cancel work orders",
         %{conn: conn, project: project} do
      {:ok, view, _html} =
        live(
          conn,
          Routes.project_run_index_path(conn, :index, project.id,
            filters: %{pending: true}
          )
        )

      html =
        render_click(view, "bulk-cancel", %{type: "selected"})

      assert html =~ "You are not authorized to perform this action."
    end

    @tag role: :editor
    test "mixed-state selection disables both cancel and retry",
         %{conn: conn, project: project, workflow: workflow} do
      trigger = List.first(workflow.triggers)
      dataclip = insert(:dataclip, project: project)

      _pending_wo =
        insert(:workorder,
          workflow: workflow,
          trigger: trigger,
          dataclip: dataclip,
          state: :pending,
          last_activity: DateTime.utc_now()
        )
        |> with_run(
          state: :available,
          dataclip: dataclip,
          starting_trigger: trigger
        )

      {:ok, view, _html} =
        live_async(
          conn,
          Routes.project_run_index_path(conn, :index, project.id,
            filters: %{pending: true, failed: true}
          )
        )

      # Select all (mix of pending and failed)
      render_change(view, "toggle_all_selections", %{
        all_selections: true
      })

      # Cancel should be disabled (mixed states)
      assert has_element?(view, "#bulk-cancel-disabled-tooltip")
      # Retry should be disabled (mixed states)
      assert has_element?(view, "#bulk-retry-disabled-tooltip")
    end

    @tag role: :editor
    test "cancel work order that is no longer pending",
         %{conn: conn, project: project, workflow: workflow} do
      trigger = List.first(workflow.triggers)
      dataclip = insert(:dataclip, project: project)

      # Create a WO that looks pending but its run is already claimed
      wo =
        insert(:workorder,
          workflow: workflow,
          trigger: trigger,
          dataclip: dataclip,
          state: :running,
          last_activity: DateTime.utc_now()
        )
        |> with_run(
          state: :claimed,
          dataclip: dataclip,
          starting_trigger: trigger,
          claimed_at: build(:timestamp)
        )

      {:ok, view, _html} =
        live_async(
          conn,
          Routes.project_run_index_path(conn, :index, project.id,
            filters: %{running: true}
          )
        )

      html =
        render_click(view, "cancel", %{
          "workorder_id" => wo.id
        })

      assert html =~ "Work order could not be cancelled"
    end

    @tag role: :editor
    test "cancel button disappears when run is claimed while page is live",
         %{conn: conn, project: project, workflow: workflow} do
      trigger = List.first(workflow.triggers)
      dataclip = insert(:dataclip, project: project)

      pending_wo =
        insert(:workorder,
          workflow: workflow,
          trigger: trigger,
          dataclip: dataclip,
          state: :pending,
          last_activity: DateTime.utc_now()
        )
        |> with_run(
          state: :available,
          dataclip: dataclip,
          starting_trigger: trigger
        )

      {:ok, view, _html} =
        live_async(
          conn,
          Routes.project_run_index_path(conn, :index, project.id,
            filters: %{pending: true, running: true}
          )
        )

      assert has_element?(view, "button#cancel-wo-#{pending_wo.id}")

      run = List.first(pending_wo.runs)

      {:ok, run} =
        run |> Ecto.Changeset.change(state: :claimed) |> Repo.update()

      {:ok, _wo} = WorkOrders.update_state(run)

      render(view)

      refute has_element?(view, "button#cancel-wo-#{pending_wo.id}")
    end

    @tag role: :editor
    test "cancel-run with nonexistent run shows error",
         %{conn: conn, project: project} do
      {:ok, view, _html} =
        live_async(
          conn,
          Routes.project_run_index_path(conn, :index, project.id,
            filters: %{pending: true}
          )
        )

      html =
        render_click(view, "cancel-run", %{"run_id" => Ecto.UUID.generate()})

      assert html =~ "Run not found."
    end

    @tag role: :editor
    test "cancel-run when run already claimed shows info flash",
         %{conn: conn, project: project, workflow: workflow} do
      trigger = List.first(workflow.triggers)
      dataclip = insert(:dataclip, project: project)

      pending_wo =
        insert(:workorder,
          workflow: workflow,
          trigger: trigger,
          dataclip: dataclip,
          state: :running,
          last_activity: DateTime.utc_now()
        )
        |> with_run(
          state: :claimed,
          dataclip: dataclip,
          starting_trigger: trigger,
          claimed_at: build(:timestamp)
        )

      run = List.first(pending_wo.runs)

      {:ok, view, _html} =
        live_async(
          conn,
          Routes.project_run_index_path(conn, :index, project.id,
            filters: %{running: true}
          )
        )

      html = render_click(view, "cancel-run", %{"run_id" => run.id})

      assert html =~ "no longer available"
    end

    @tag role: :viewer
    test "viewers cannot cancel individual runs",
         %{conn: conn, project: project} do
      {:ok, view, _html} =
        live(
          conn,
          Routes.project_run_index_path(conn, :index, project.id)
        )

      html =
        render_click(view, "cancel-run", %{"run_id" => Ecto.UUID.generate()})

      assert html =~ "You are not authorized to perform this action."
    end

    @tag role: :editor
    test "bulk cancel all matching work orders via async path",
         %{conn: conn, project: project, workflow: workflow} do
      trigger = List.first(workflow.triggers)
      dataclip = insert(:dataclip, project: project)

      for _i <- 1..3 do
        insert(:workorder,
          workflow: workflow,
          trigger: trigger,
          dataclip: dataclip,
          state: :pending,
          last_activity: DateTime.utc_now()
        )
        |> with_run(
          state: :available,
          dataclip: dataclip,
          starting_trigger: trigger
        )
      end

      {:ok, view, _html} =
        live_async(
          conn,
          Routes.project_run_index_path(conn, :index, project.id,
            filters: %{pending: true}
          )
        )

      # Select all
      render_change(view, "toggle_all_selections", %{
        all_selections: true
      })

      # Use "all" type to trigger the async path
      result = render_click(view, "bulk-cancel", %{type: "all"})
      {:ok, _view, html} = follow_redirect(result, conn)

      assert html =~ "Cancelling runs for"
      assert html =~ "work order"
      assert html =~ "in the background"
    end
  end

  describe "Export History" do
    test "export history button is present", %{conn: conn, project: project} do
      {:ok, view, _html} =
        live_async(
          conn,
          Routes.project_run_index_path(conn, :index, project.id)
        )

      assert has_element?(view, "button#export-history-button")
    end
  end
end
