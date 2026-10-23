defmodule LightningWeb.RunLive.IndexTest do
  use LightningWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Lightning.Factories

  alias Lightning.WorkOrders

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
      workflow: workflow
    }
  end

  # The work orders tab is drawn by React from data-props: the chips, the
  # table, the selection and the modals are tested in the design system's
  # HistoryWorkOrdersPage.test.tsx. These tests cover what the server sends
  # and how it answers the page's events.
  @page "#history-work-orders-page"

  defp history_path(project, filters \\ %{}),
    do: ~p"/projects/#{project}/history?#{%{filters: filters}}"

  describe "a killed step" do
    test "with an unknown error type logs a warning and reports to Sentry; known ones do neither",
         %{conn: conn, project: project, workflow: workflow, jobs: [job | _]} do
      Mox.stub(Lightning.MockConfig, :sentry, fn -> Lightning.MockSentry end)

      test_pid = self()

      Mox.stub(Lightning.MockSentry, :capture_message, fn msg, opts ->
        send(test_pid, {:sentry, msg, opts})
        :ok
      end)

      snapshot = Lightning.Workflows.Snapshot.get_current_for(workflow)
      trigger = List.first(workflow.triggers)

      [unknown_kill, _known_kill] =
        for error_type <- ["SomeFutureWorkerError", "OOMError"] do
          dataclip = insert(:dataclip, project: project)

          insert(:workorder,
            workflow: workflow,
            trigger: trigger,
            dataclip: dataclip,
            state: :killed,
            last_activity: DateTime.utc_now()
          )
          |> with_run(
            state: :killed,
            dataclip: dataclip,
            starting_trigger: trigger,
            finished_at: build(:timestamp),
            steps: [
              build(:step,
                job: job,
                snapshot: snapshot,
                input_dataclip: dataclip,
                started_at: build(:timestamp),
                finished_at: build(:timestamp),
                exit_reason: "kill",
                error_type: error_type
              )
            ]
          )
        end

      log =
        ExUnit.CaptureLog.capture_log(fn ->
          {:ok, view, _html} = live_async(conn, history_path(project))

          # The page's step icon is drawn from these two.
          assert %{"runs" => [%{"steps" => [step]}]} = row(view, unknown_kill)

          assert %{
                   "exitReason" => "kill",
                   "errorType" => "SomeFutureWorkerError"
                 } =
                   step

          # A live update draws the page again with the same step.
          send(view.pid, %WorkOrders.Events.WorkOrderUpdated{
            work_order: unknown_kill
          })

          render(view)
        end)

      assert [_once] =
               Regex.scan(
                 ~r/Unknown kill error_type: "SomeFutureWorkerError"/,
                 log
               )

      refute log =~ "OOMError"

      assert_received {:sentry, "Unknown kill error_type", opts}
      assert opts[:level] == :warning
      assert opts[:extra][:error_type] == "SomeFutureWorkerError"

      refute_received {:sentry, _, _}
    end
  end

  describe "a step's job" do
    test "is named from the step when its snapshot is missing or lacks it, and says when it was deleted",
         %{conn: conn, project: project, workflow: workflow} do
      trigger = List.first(workflow.triggers)
      dataclip = insert(:dataclip, project: project)
      added_job = insert(:job, workflow: workflow, name: "added after snapshot")
      old_snapshot = insert(:snapshot, workflow: workflow)
      [deleted_job | _] = old_snapshot.jobs

      steps =
        [
          [job: added_job, snapshot: nil],
          [job: added_job],
          [job: nil, job_id: deleted_job.id, snapshot: old_snapshot]
        ]
        |> Enum.map(fn attrs ->
          build(
            :step,
            [
              snapshot: Lightning.Workflows.Snapshot.get_current_for(workflow),
              input_dataclip: dataclip,
              started_at: build(:timestamp)
            ] ++ attrs
          )
        end)

      work_order =
        insert(:workorder,
          workflow: workflow,
          trigger: trigger,
          dataclip: dataclip,
          last_activity: DateTime.utc_now()
        )
        |> with_run(
          state: :started,
          dataclip: dataclip,
          starting_trigger: trigger,
          steps: steps
        )

      {:ok, view, _html} = live_async(conn, history_path(project))

      %{"runs" => [%{"steps" => steps}]} = row(view, work_order)

      assert Enum.sort(Enum.map(steps, &{&1["jobName"], &1["jobDeleted"]})) ==
               Enum.sort([
                 {added_job.name, false},
                 {added_job.name, false},
                 {deleted_job.name, true}
               ])
    end
  end

  defp pending_work_order(workflow) do
    trigger = List.first(workflow.triggers)
    dataclip = insert(:dataclip, project: workflow.project)

    insert(:workorder,
      workflow: workflow,
      trigger: trigger,
      dataclip: dataclip,
      state: :pending,
      last_activity: DateTime.utc_now()
    )
    |> with_run(state: :available, dataclip: dataclip, starting_trigger: trigger)
  end

  # Its run has been claimed by a worker, so it can no longer be cancelled.
  defp running_work_order(workflow) do
    trigger = List.first(workflow.triggers)
    dataclip = insert(:dataclip, project: workflow.project)

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
  end

  # A failed work order in a project the user isn't viewing.
  defp foreign_failed_work_order do
    %{jobs: [job], triggers: [trigger]} =
      workflow = insert(:simple_workflow, project: insert(:project))

    dataclip = insert(:dataclip, project: workflow.project)

    insert(:workorder,
      workflow: workflow,
      trigger: trigger,
      dataclip: dataclip,
      state: :failed
    )
    |> with_run(
      state: :failed,
      dataclip: dataclip,
      starting_trigger: trigger,
      steps: [
        build(:step, job: job, input_dataclip: dataclip, exit_reason: "fail")
      ]
    )
  end

  defp run_count(work_order),
    do: Repo.aggregate(Ecto.assoc(work_order, :runs), :count)

  defp row(view, work_order) do
    Enum.find(page_props(view, @page)["rows"], &(&1["id"] == work_order.id))
  end

  # Jobs the view enqueues wait in the queue, as in dev, instead of running
  # inline; `Oban.drain_queue/2` runs them. Oban runs a job inline if the
  # view or any of its callers (this test) is inline, so both are set.
  defp defer_jobs(view) do
    Process.put(:oban_testing, :manual)

    :sys.replace_state(view.pid, fn state ->
      Process.put(:oban_testing, :manual)
      state
    end)
  end

  # The project's next history search, once it has read the rows, waits for
  # `:go` before it answers the page, and says `{:searched, pid}` meanwhile.
  defp hold_next_search(project) do
    test = self()
    id = {__MODULE__, make_ref()}

    :telemetry.attach(
      id,
      [:lightning, :ui, :projects, :history, :stop],
      fn _event, _measurements, %{project_id: project_id}, _config ->
        if project_id == project.id do
          :telemetry.detach(id)
          send(test, {:searched, self()})

          receive do
            :go -> :ok
          end
        end
      end,
      nil
    )

    on_exit(fn -> :telemetry.detach(id) end)
  end

  describe "retry" do
    @tag role: :viewer
    test "Project viewers can't rerun runs", %{
      conn: conn,
      project: project,
      jobs: [job_a | _rest],
      work_order_1: work_order_1
    } do
      {:ok, view, _html} = live_async(conn, history_path(project))

      push_page_event(view, @page, "bulk-rerun", %{
        "type" => "all",
        "job" => job_a.id
      })

      assert_reply(view, %{
        error: "You are not authorized to perform this action."
      })

      push_page_event(view, @page, "bulk-rerun", %{
        "type" => "selected",
        "workorder_ids" => [work_order_1.id],
        "job" => nil
      })

      assert_reply(view, %{
        error: "You are not authorized to perform this action."
      })

      push_page_event(view, @page, "rerun", %{
        "run_id" => Ecto.UUID.generate(),
        "step_id" => Ecto.UUID.generate()
      })

      assert_reply(view, %{
        error: "You are not authorized to perform this action."
      })

      assert run_count(work_order_1) == 1
    end

    @tag role: :editor
    test "Project editors can rerun runs from a job", %{
      conn: conn,
      project: project,
      jobs: [job_a | _rest],
      work_order_1: work_order_1
    } do
      {:ok, view, _html} = live_async(conn, history_path(project))

      {:ok, view, html} =
        push_page_event(view, @page, "bulk-rerun", %{
          "type" => "all",
          "job" => job_a.id
        })
        |> follow_redirect(conn)

      assert html =~ "New runs enqueued for 2 workorders"

      render_async(view)

      {:ok, _view, html} =
        push_page_event(view, @page, "bulk-rerun", %{
          "type" => "selected",
          "workorder_ids" => [work_order_1.id],
          "job" => job_a.id
        })
        |> follow_redirect(conn)

      # this is zero because the previous retried run has no steps
      assert html =~ "New run enqueued for 0 workorder"
    end

    @tag role: :editor
    test "Project editors can rerun from the start, all matching or selected",
         %{
           conn: conn,
           project: project,
           work_order_1: work_order_1
         } do
      {:ok, view, _html} = live_async(conn, history_path(project))

      {:ok, view, html} =
        push_page_event(view, @page, "bulk-rerun", %{
          "type" => "all",
          "job" => nil
        })
        |> follow_redirect(conn)

      assert html =~ "New runs enqueued for 2 workorders"

      render_async(view)

      # A row's own Retry is a selection of one.
      {:ok, _view, html} =
        push_page_event(view, @page, "bulk-rerun", %{
          "type" => "selected",
          "workorder_ids" => [work_order_1.id],
          "job" => nil
        })
        |> follow_redirect(conn)

      assert html =~ "New run enqueued for 1 workorder"
    end

    # The background retry often lands while the navigated page is still
    # searching: the search has read the old rows, and the job's events
    # arrive before its answer.
    @tag role: :editor
    test "retry all redraws the rows when the retry lands during the page's search",
         %{
           conn: conn,
           project: project,
           work_order_1: work_order_1,
           work_order_2: work_order_2
         } do
      {:ok, view, _html} = live_async(conn, history_path(project))
      defer_jobs(view)
      hold_next_search(project)

      {:ok, view, _html} =
        push_page_event(view, @page, "bulk-rerun", %{
          "type" => "all",
          "job" => nil
        })
        |> follow_redirect(conn)

      assert_receive {:searched, search}
      Oban.drain_queue(Lightning.Oban, queue: :scheduler)
      # The page has handled the job's events; then the search answers
      render(view)
      ref = Process.monitor(search)
      send(search, :go)
      assert_receive {:DOWN, ^ref, _, _, _}
      # and the page searches again
      render_async(view)

      assert row(view, work_order_1)["state"] == "pending"
      assert row(view, work_order_2)["state"] == "pending"
    end

    @tag role: :editor
    test "a refused bulk retry says why", %{
      conn: conn,
      project: project,
      work_order_1: work_order_1
    } do
      {:ok, view, _html} = live_async(conn, history_path(project))

      Mox.stub(
        Lightning.Extensions.MockUsageLimiter,
        :limit_action,
        &Lightning.Extensions.StubUsageLimiter.limit_action/2
      )

      push_page_event(view, @page, "bulk-rerun", %{
        "type" => "selected",
        "workorder_ids" => [work_order_1.id],
        "job" => nil
      })

      assert_reply(view, %{error: "Runs limit exceeded"})
    end

    @tag role: :editor
    test "bulk retry and cancel act only on work orders the page is showing",
         %{
           conn: conn,
           project: project,
           work_order_1: work_order_1
         } do
      other_wo = foreign_failed_work_order()
      [other_job] = other_wo.workflow.jobs
      other_pending = pending_work_order(other_wo.workflow)

      {:ok, view, _html} = live_async(conn, history_path(project))

      for ids <- [[other_wo.id], [work_order_1.id, other_wo.id], [], "nope"] do
        push_page_event(view, @page, "bulk-rerun", %{
          "type" => "selected",
          "workorder_ids" => ids,
          "job" => nil
        })

        assert_reply(view, %{error: "Work order not found."})
      end

      push_page_event(view, @page, "bulk-rerun", %{
        "type" => "selected",
        "workorder_ids" => [other_wo.id],
        "job" => other_job.id
      })

      assert_reply(view, %{error: "Work order not found."})

      push_page_event(view, @page, "bulk-cancel", %{
        "type" => "selected",
        "workorder_ids" => [other_pending.id]
      })

      assert_reply(view, %{error: "Work order not found."})

      refute_enqueued(worker: Lightning.WorkOrders.RetryManyWorkOrdersJob)
      assert run_count(other_wo) == 1
      assert run_count(work_order_1) == 1

      assert [%{state: :available}] =
               Repo.preload(other_pending, :runs, force: true).runs
    end

    @tag role: :editor
    test "Retry asks whether the project may start that many runs", %{
      conn: conn,
      project: project
    } do
      {:ok, view, _html} = live_async(conn, history_path(project))

      push_page_event(view, @page, "validate_bulk_rerun", %{"count" => 2})
      assert_reply(view, %{})

      Mox.stub(
        Lightning.Extensions.MockUsageLimiter,
        :limit_action,
        &Lightning.Extensions.StubUsageLimiter.limit_action/2
      )

      push_page_event(view, @page, "validate_bulk_rerun", %{"count" => 2})
      assert_reply(view, %{error: "Runs limit exceeded"})
    end

    @tag role: :editor
    test "Project editors can rerun from a step", %{
      conn: conn,
      project: project,
      work_order_1: work_order_1
    } do
      [run] = work_order_1.runs
      [step | _] = Repo.preload(run, :steps).steps

      {:ok, view, _html} = live_async(conn, history_path(project))

      push_page_event(view, @page, "rerun", %{
        "run_id" => run.id,
        "step_id" => step.id
      })

      assert_reply(view, %{})
      assert run_count(work_order_1) == 2
    end

    @tag role: :editor
    test "Project editors can't rerun a step when the limit has been reached",
         %{conn: conn, project: project, work_order_1: work_order_1} do
      [run] = work_order_1.runs
      [step | _] = Repo.preload(run, :steps).steps

      {:ok, view, _html} = live_async(conn, history_path(project))

      Mox.stub(
        Lightning.Extensions.MockUsageLimiter,
        :limit_action,
        &Lightning.Extensions.StubUsageLimiter.limit_action/2
      )

      push_page_event(view, @page, "rerun", %{
        "run_id" => run.id,
        "step_id" => step.id
      })

      assert_reply(view, %{error: "Runs limit exceeded"})
      assert run_count(work_order_1) == 1
    end

    @tag role: :editor
    test "an editor cannot rerun a run that belongs to another project", %{
      conn: conn,
      project: project
    } do
      # A run living in a project unrelated to the one being viewed.
      other_wo = foreign_failed_work_order()
      [other_run] = other_wo.runs
      [other_step] = Repo.preload(other_run, :steps).steps

      {:ok, view, _html} = live(conn, history_path(project))

      push_page_event(view, @page, "rerun", %{
        "run_id" => other_run.id,
        "step_id" => other_step.id
      })

      assert_reply(view, %{error: "Run not found."})

      # the foreign run was not retried: no new run inserted for its work order
      assert run_count(other_wo) == 1
    end

    @tag role: :editor
    test "rerun with a malformed or mismatched id returns not-found, not a crash",
         %{conn: conn, project: project, work_order_1: work_order_1} do
      {:ok, view, _html} = live(conn, history_path(project))

      # a non-UUID run id must not reach (and crash) the query
      push_page_event(view, @page, "rerun", %{
        "run_id" => "not-a-uuid",
        "step_id" => Ecto.UUID.generate()
      })

      assert_reply(view, %{error: "Run not found."})

      # a valid in-project run, but a step that is not one of its steps
      [run] = work_order_1.runs

      push_page_event(view, @page, "rerun", %{
        "run_id" => run.id,
        "step_id" => Ecto.UUID.generate()
      })

      assert_reply(view, %{error: "Run not found."})
    end

    @tag role: :editor
    test "crafted payloads get an error back, not a crash",
         %{conn: conn, project: project} do
      {:ok, view, _html} = live_async(conn, history_path(project))

      for {event, payload, error} <- [
            {"cancel", %{"workorder_id" => "x"}, "Work order not found."},
            {"cancel-run", %{"run_id" => "x"}, "Run not found."},
            {"bulk-rerun", %{"type" => "all", "job" => "x"},
             "Work order not found."},
            {"validate_bulk_rerun", %{}, "Invalid request"},
            {"validate_bulk_rerun", %{"count" => "1"}, "Invalid request"}
          ] do
        push_page_event(view, @page, event, payload)
        assert_reply(view, %{error: ^error})
      end

      # Retry from a job when nothing matching can be retried.
      {:ok, view, _html} =
        live_async(
          conn,
          history_path(project, %{workflow_id: Ecto.UUID.generate()})
        )

      assert {:error, {:live_redirect, _}} =
               push_page_event(view, @page, "bulk-rerun", %{
                 "type" => "all",
                 "job" => Ecto.UUID.generate()
               })
    end
  end

  describe "cancel" do
    @tag role: :editor
    test "bulk cancel for selected pending work orders",
         %{conn: conn, project: project, workflow: workflow} do
      pending_wo = pending_work_order(workflow)

      {:ok, view, _html} =
        live_async(conn, history_path(project, %{pending: true}))

      {:ok, _view, html} =
        push_page_event(view, @page, "bulk-cancel", %{
          "type" => "selected",
          "workorder_ids" => [pending_wo.id]
        })
        |> follow_redirect(conn)

      assert html =~ "Cancelled 1 run"
    end

    @tag role: :editor
    test "bulk cancel all matching work orders via async path",
         %{conn: conn, project: project, workflow: workflow} do
      for _i <- 1..3, do: pending_work_order(workflow)

      {:ok, view, _html} =
        live_async(conn, history_path(project, %{pending: true}))

      {:ok, _view, html} =
        push_page_event(view, @page, "bulk-cancel", %{"type" => "all"})
        |> follow_redirect(conn)

      assert html =~ "Cancelling runs for 3 work orders in the background"
    end

    @tag role: :editor
    test "single work order cancel from its row",
         %{conn: conn, project: project, workflow: workflow} do
      pending_wo = pending_work_order(workflow)

      {:ok, view, _html} =
        live_async(conn, history_path(project, %{pending: true}))

      html =
        push_page_event(view, @page, "cancel", %{
          "workorder_id" => pending_wo.id
        })

      assert_reply(view, %{})
      assert html =~ "Work order cancelled."
    end

    @tag role: :editor
    test "cancel work order that is no longer pending",
         %{conn: conn, project: project, workflow: workflow} do
      wo = running_work_order(workflow)

      {:ok, view, _html} =
        live_async(conn, history_path(project, %{running: true}))

      html = push_page_event(view, @page, "cancel", %{"workorder_id" => wo.id})

      assert_reply(view, %{})
      assert html =~ "Work order could not be cancelled"
    end

    @tag role: :editor
    test "a run waiting for a worker can be cancelled from its row",
         %{conn: conn, project: project, workflow: workflow} do
      pending_wo = pending_work_order(workflow)
      run = List.first(pending_wo.runs)

      {:ok, view, _html} =
        live_async(conn, history_path(project, %{pending: true}))

      html = push_page_event(view, @page, "cancel-run", %{"run_id" => run.id})

      assert_reply(view, %{})
      assert html =~ "Run cancelled."
    end

    @tag role: :editor
    test "cancel-run with nonexistent run says so",
         %{conn: conn, project: project} do
      {:ok, view, _html} = live_async(conn, history_path(project))

      push_page_event(view, @page, "cancel-run", %{
        "run_id" => Ecto.UUID.generate()
      })

      assert_reply(view, %{error: "Run not found."})
    end

    @tag role: :editor
    test "cancel-run when run already claimed shows info flash",
         %{conn: conn, project: project, workflow: workflow} do
      wo = running_work_order(workflow)

      run = List.first(wo.runs)

      {:ok, view, _html} =
        live_async(conn, history_path(project, %{running: true}))

      html = push_page_event(view, @page, "cancel-run", %{"run_id" => run.id})

      assert_reply(view, %{})
      assert html =~ "no longer available"
    end

    @tag role: :viewer
    test "viewers cannot cancel work orders or runs",
         %{conn: conn, project: project, workflow: workflow} do
      pending_wo = pending_work_order(workflow)

      {:ok, view, _html} =
        live_async(conn, history_path(project, %{pending: true}))

      for {event, payload} <- [
            {"bulk-cancel",
             %{"type" => "selected", "workorder_ids" => [pending_wo.id]}},
            {"bulk-cancel", %{"type" => "all"}},
            {"cancel", %{"workorder_id" => pending_wo.id}},
            {"cancel-run", %{"run_id" => hd(pending_wo.runs).id}}
          ] do
        push_page_event(view, @page, event, payload)

        assert_reply(view, %{
          error: "You are not authorized to perform this action."
        })
      end

      assert [%{state: :available}] =
               Repo.preload(pending_wo, :runs, force: true).runs
    end

    @tag role: :editor
    test "a pending work order's state follows its run while the page is open",
         %{conn: conn, project: project, workflow: workflow} do
      pending_wo = pending_work_order(workflow)

      {:ok, view, _html} =
        live_async(
          conn,
          history_path(project, %{pending: true, running: true})
        )

      assert %{"state" => "pending"} = row(view, pending_wo)

      run = List.first(pending_wo.runs)

      {:ok, run} =
        run |> Ecto.Changeset.change(state: :claimed) |> Repo.update()

      {:ok, _wo} = WorkOrders.update_state(run)

      render(view)

      assert %{"state" => "running"} = row(view, pending_wo)
    end
  end

  describe "export" do
    @tag role: :viewer
    test "a viewer cannot start a history export", %{
      conn: conn,
      project: project
    } do
      {:ok, view, _html} = live_async(conn, history_path(project))

      assert page_props(view, @page)["canRunWorkflow"] == false

      push_page_event(view, @page, "confirm-export")

      assert_reply(view, %{
        error: "You are not authorized to perform this action."
      })

      refute Enum.any?(
               Repo.all(Lightning.Projects.File),
               &(&1.type == :export)
             )
    end

    @tag role: :editor
    test "an editor can start a history export", %{conn: conn, project: project} do
      {:ok, view, _html} = live_async(conn, history_path(project))

      assert page_props(view, @page)["canRunWorkflow"] == true

      html = push_page_event(view, @page, "confirm-export")

      assert_reply(view, %{})
      assert html =~ "started successfully"

      assert Enum.any?(
               Repo.all(Lightning.Projects.File),
               &(&1.type == :export)
             )
    end
  end

  describe "filters" do
    test "come from the URL, defaulting to the last 30 days of activity, logs searched",
         %{conn: conn, project: project} do
      {:ok, view, _html} = live_async(conn, history_path(project))

      assert %{
               "filters" => %{
                 "workflowId" => nil,
                 "statuses" => [],
                 "activityAfter" => activity_after,
                 "searchTerm" => "",
                 "searchFields" => ["log"],
                 "errorSignature" => nil,
                 "runStatuses" => [],
                 "workorderId" => nil
               },
               "sort" => %{"key" => "last_activity", "direction" => "desc"},
               "searchLimit" => search_limit
             } = page_props(view, @page)

      assert search_limit == Lightning.Invocation.get_workorders_count_limit()

      {:ok, activity_after, 0} = DateTime.from_iso8601(activity_after)
      days_ago = DateTime.diff(DateTime.utc_now(), activity_after, :day)
      assert days_ago in 29..30

      {:ok, view, _html} =
        live_async(
          conn,
          history_path(project, %{
            failed: true,
            success: true,
            body: true,
            log: "false",
            search_term: "abc",
            wo_date_after: "2025-01-01T00:00",
            sort_by: "inserted_at",
            sort_direction: "asc"
          })
        )

      assert %{
               "filters" => %{
                 "statuses" => ["success", "failed"],
                 "searchFields" => ["body"],
                 "searchTerm" => "abc",
                 "receivedAfter" => "2025-01-01T00:00:00Z",
                 "activityAfter" => nil
               },
               "sort" => %{"key" => "inserted_at", "direction" => "asc"}
             } = page_props(view, @page)
    end

    test "the workflow filter narrows the rows, and lists only this project's workflows",
         %{conn: conn, project: project, workflow: workflow, jobs: jobs} do
      other = insert(:workflow, project: project, name: "other")
      foreign = insert(:workflow, project: insert(:project))

      {:ok, view, _html} =
        live_async(conn, history_path(project, %{workflow_id: other.id}))

      props = page_props(view, @page)
      assert props["filters"]["workflowId"] == other.id
      assert props["rows"] == []

      ids = Enum.map(props["workflows"], & &1["id"])
      assert workflow.id in ids
      assert other.id in ids
      refute foreign.id in ids

      # Each workflow brings its jobs, by name, for "Retry from".
      assert %{"jobs" => listed} =
               Enum.find(props["workflows"], &(&1["id"] == workflow.id))

      assert listed ==
               jobs
               |> Enum.sort_by(& &1.name)
               |> Enum.map(&%{"id" => &1.id, "name" => &1.name})

      {:ok, view, _html} =
        live_async(conn, history_path(project, %{workflow_id: workflow.id}))

      assert length(page_props(view, @page)["rows"]) == 2
    end

    test "the work order and error signature filters", %{
      conn: conn,
      project: project,
      work_order_1: wo,
      jobs: [job | _]
    } do
      {:ok, view, _html} =
        live_async(
          conn,
          history_path(project, %{
            workorder_id: wo.id,
            error_signature_exit_reason: "fail",
            error_signature_error_type: "AdaptorError",
            error_signature_job_id: job.id
          })
        )

      assert %{
               "workorderId" => wo_id,
               "errorSignature" => %{
                 "exitReason" => "fail",
                 "errorType" => "AdaptorError",
                 "jobId" => job_id,
                 "jobName" => job_name
               }
             } = page_props(view, @page)["filters"]

      assert {wo_id, job_id, job_name} == {wo.id, job.id, job.name}

      {:ok, view, _html} =
        live_async(
          conn,
          history_path(project, %{error_signature_exit_reason: "lost"})
        )

      assert %{"errorType" => nil, "jobId" => nil, "jobName" => nil} =
               page_props(view, @page)["filters"]["errorSignature"]
    end

    # The name is read back from the id, so the read is scoped to the project
    # the page is on — a hand-edited id from elsewhere names nothing here.
    test "the error signature names no job outside the project",
         %{conn: conn, project: project} do
      other_job = insert(:job, workflow: build(:workflow))

      {:ok, view, _html} =
        live_async(
          conn,
          history_path(project, %{
            error_signature_exit_reason: "fail",
            error_signature_job_id: other_job.id
          })
        )

      assert %{"jobId" => job_id, "jobName" => nil} =
               page_props(view, @page)["filters"]["errorSignature"]

      assert job_id == other_job.id
    end

    # A band of a bar on the workflow health page's runs chart links here, and
    # sets both.
    test "a runs-chart band's run statuses and run dates", %{
      conn: conn,
      project: project
    } do
      {:ok, view, _html} =
        live_async(
          conn,
          history_path(project, %{
            run_date_after: "2026-09-08T02:00:00Z",
            run_date_before: "2026-09-08T04:00:00Z",
            run_status: ["failed", "crashed"]
          })
        )

      assert %{
               "runStatuses" => ["failed", "crashed"],
               "runCreatedAfter" => "2026-09-08T02:00:00Z",
               "runCreatedBefore" => "2026-09-08T04:00:00Z"
             } = page_props(view, @page)["filters"]

      {:ok, view, _html} =
        live_async(
          conn,
          history_path(project, %{run_date_after: "2026-09-08T02:00:00Z"})
        )

      assert %{"runStatuses" => [], "runCreatedBefore" => nil} =
               page_props(view, @page)["filters"]
    end
  end

  describe "channel logs tab" do
    test "the tab bar shows only with experimental features", %{
      conn: conn,
      project: project,
      user: user
    } do
      {:ok, view, _html} = live_async(conn, history_path(project))

      assert %{
               "channelsEnabled" => false,
               "workOrdersHref" => work_orders_href,
               "channelLogsHref" => channel_logs_href
             } = page_props(view, @page)

      assert work_orders_href == ~p"/projects/#{project}/history"
      assert channel_logs_href == ~p"/projects/#{project}/history/channels"

      Lightning.Accounts.update_user_preferences(user, %{
        "experimental_features" => true
      })

      {:ok, view, _html} = live_async(conn, history_path(project))

      assert page_props(view, @page)["channelsEnabled"] == true
    end

    # The channel logs tab is drawn by React from data-props: the filter chip,
    # the tab bar, the empty state and the row cells are tested in the design
    # system's HistoryChannelLogsPage.test.tsx. These tests cover what the
    # server sends for it.
    @channel_logs "#history-channel-logs-page"

    test "navigating to channel logs tab renders channel logs content", %{
      conn: conn,
      project: project,
      user: user
    } do
      Lightning.Accounts.update_user_preferences(user, %{
        "experimental_features" => true
      })

      channel = insert(:channel, project: project, name: "test-channel")

      {:ok, view, _html} =
        live(conn, ~p"/projects/#{project.id}/history/channels")

      assert %{
               "project" => %{"id" => project_id},
               "projectLabel" => project_label,
               "channelsEnabled" => true,
               "channels" => [%{"id" => channel_id, "name" => "test-channel"}],
               "channelId" => nil,
               "rows" => [],
               "page" => %{"number" => 1, "size" => 10, "totalEntries" => 0}
             } = page_props(view, @channel_logs)

      assert project_id == project.id
      assert project_label == project.name
      assert channel_id == channel.id
    end

    test "channel logs tab says the tab bar is hidden without experimental features",
         %{conn: conn, project: project} do
      {:ok, view, _html} =
        live(conn, ~p"/projects/#{project.id}/history/channels")

      assert %{"channelsEnabled" => false} = page_props(view, @channel_logs)
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

      request =
        insert(:channel_request,
          channel: channel,
          channel_snapshot: snapshot,
          state: :success,
          started_at: DateTime.utc_now()
        )

      {:ok, view, _html} =
        live(conn, ~p"/projects/#{project.id}/history/channels")

      assert %{
               "rows" => [
                 %{
                   "id" => id,
                   "requestId" => request_id,
                   "channelName" => "test-channel",
                   "state" => "success",
                   "requestPath" => nil,
                   "errorMessage" => nil
                 }
               ],
               "page" => %{"totalEntries" => 1}
             } = page_props(view, @channel_logs)

      assert id == request.id
      assert request_id == request.request_id
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

      {:ok, view, _html} =
        live(
          conn,
          ~p"/projects/#{project.id}/history/channels?#{%{filters: %{channel_id: ch1.id}}}"
        )

      props = page_props(view, @channel_logs)
      assert props["channelId"] == ch1.id
      assert Enum.map(props["rows"], & &1["id"]) == [cr1.id]
      refute cr2.id in Enum.map(props["rows"], & &1["id"])

      # A malformed filter is dropped, as the old component's search params did.
      {:ok, view, _html} =
        live(
          conn,
          ~p"/projects/#{project.id}/history/channels?#{%{filters: %{channel_id: "nope"}}}"
        )

      props = page_props(view, @channel_logs)
      assert props["channelId"] == nil
      assert length(props["rows"]) == 2

      # A well-formed id that is not one of this project's channels is also
      # "any channel", so the chip and the rows agree.
      {:ok, view, _html} =
        live(
          conn,
          ~p"/projects/#{project.id}/history/channels?#{%{filters: %{channel_id: Ecto.UUID.generate()}}}"
        )

      props = page_props(view, @channel_logs)
      assert props["channelId"] == nil
      assert length(props["rows"]) == 2

      # Filters that are not a map do not crash the page.
      {:ok, view, _html} =
        live(conn, ~p"/projects/#{project.id}/history/channels?filters=abc")

      assert page_props(view, @channel_logs)["channelId"] == nil
    end

    test "work orders content is hidden on channel logs tab", %{
      conn: conn,
      project: project,
      user: user
    } do
      Lightning.Accounts.update_user_preferences(user, %{
        "experimental_features" => true
      })

      {:ok, view, html} =
        live(conn, ~p"/projects/#{project.id}/history/channels")

      assert has_element?(view, @channel_logs)
      refute html =~ "history-work-orders-page"

      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/history")
      refute has_element?(view, @channel_logs)
      assert has_element?(view, @page)
    end

    test "old /channels/requests route no longer works", %{
      conn: conn,
      project: project
    } do
      assert_raise FunctionClauseError, fn ->
        live(conn, "/projects/#{project.id}/channels/requests")
      end
    end

    test "request path column shows the path when the event has one",
         %{conn: conn, project: project, user: user} do
      Lightning.Accounts.update_user_preferences(user, %{
        "experimental_features" => true
      })

      channel = insert(:channel, project: project, name: "test-channel")

      {:ok, snapshot} =
        Lightning.Channels.get_or_create_current_snapshot(channel)

      request =
        insert(:channel_request,
          channel: channel,
          channel_snapshot: snapshot,
          state: :success,
          started_at: DateTime.utc_now()
        )

      insert(:channel_event,
        channel_request: request,
        type: :destination_response,
        request_path: "/some/upstream/path"
      )

      {:ok, view, _html} =
        live(conn, ~p"/projects/#{project.id}/history/channels")

      assert %{"rows" => [%{"requestPath" => "/some/upstream/path"}]} =
               page_props(view, @channel_logs)
    end

    test "request path column shows a dash when the request was wiped (request_path nil)",
         %{conn: conn, project: project, user: user} do
      Lightning.Accounts.update_user_preferences(user, %{
        "experimental_features" => true
      })

      project
      |> Lightning.Projects.Project.changeset(%{retention_policy: :erase_all})
      |> Lightning.Repo.update!()

      channel = insert(:channel, project: project, name: "test-channel")

      {:ok, snapshot} =
        Lightning.Channels.get_or_create_current_snapshot(channel)

      request =
        insert(:channel_request,
          channel: channel,
          channel_snapshot: snapshot,
          state: :success,
          is_wiped: true,
          started_at: DateTime.utc_now()
        )

      insert(:channel_event,
        channel_request: request,
        type: :destination_response,
        request_path: nil
      )

      {:ok, view, _html} =
        live(conn, ~p"/projects/#{project.id}/history/channels")

      # The page shows a dash for a path it does not get.
      assert %{"rows" => [%{"requestPath" => nil}]} =
               page_props(view, @channel_logs)
    end
  end
end
