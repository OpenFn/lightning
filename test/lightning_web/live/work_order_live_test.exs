defmodule LightningWeb.WorkOrderLiveTest do
  use LightningWeb.ConnCase, async: true

  import ExUnit.CaptureLog
  import Phoenix.LiveViewTest
  import Lightning.Factories
  import Lightning.TestUtils, only: [flush_dataclip_search_index: 0]

  alias Lightning.Runs
  alias Lightning.Workflows
  alias Lightning.WorkOrders.Events

  setup :register_and_log_in_user
  setup :create_project_for_current_user
  setup :stub_usage_limiter_ok

  defp setup_work_order(project) do
    dataclip = insert(:dataclip)
    %{jobs: [job]} = workflow = insert(:simple_workflow, project: project)

    {:ok, snapshot} = Workflows.Snapshot.create(workflow)

    work_order =
      work_order_for(job,
        workflow: workflow,
        snapshot: snapshot,
        dataclip: dataclip,
        runs: [
          build(:run, %{
            starting_job: job,
            dataclip: dataclip,
            snapshot: snapshot,
            steps: [
              %{
                job: job,
                snapshot: snapshot,
                started_at: build(:timestamp),
                finished_at: nil,
                exit_reason: nil,
                input_dataclip: dataclip
              }
            ]
          })
        ]
      )
      |> insert()

    {work_order, dataclip}
  end

  defp setup_work_order_with_multiple_runs(
         workflow,
         snapshot,
         trigger,
         job,
         dataclip,
         runs_params
       ) do
    work_order =
      insert(:workorder,
        workflow: workflow,
        snapshot: snapshot,
        trigger: trigger,
        dataclip: dataclip,
        last_activity: DateTime.utc_now()
      )

    runs =
      Enum.map(runs_params, fn params ->
        insert_run_with_step(work_order, trigger, dataclip, job, params)
      end)

    {work_order, runs}
  end

  defp insert_run_with_step(work_order, trigger, dataclip, job, opts) do
    state = opts[:state]
    timestamp = opts[:state_timestamp]

    insert(:run,
      work_order: work_order,
      starting_trigger: trigger,
      dataclip: dataclip,
      snapshot: work_order.snapshot,
      state: state,
      "#{state}_at": timestamp,
      steps: [
        build(:step,
          job: job,
          snapshot: work_order.snapshot,
          started_at: build(:timestamp),
          finished_at: build(:timestamp),
          input_dataclip: dataclip
        )
      ]
    )
  end

  # The work orders tab is drawn by React from data-props: what a row, a run
  # and a step look like is tested in the design system's
  # HistoryWorkOrdersPage.test.tsx. These tests cover what the server sends.
  @page "#history-work-orders-page"

  defp rows(view), do: page_props(view, @page)["rows"]

  defp row(view, work_order),
    do: Enum.find(rows(view), &(&1["id"] == work_order.id))

  defp row_ids(view), do: Enum.map(rows(view), & &1["id"])

  describe "Index" do
    test "renders a banner when run limit has been reached", %{
      conn: conn,
      project: %{id: project_id}
    } do
      Mox.stub(
        Lightning.Extensions.MockUsageLimiter,
        :check_limits,
        &Lightning.Extensions.StubUsageLimiter.check_limits/1
      )

      {:ok, _view, html} = live(conn, ~p"/projects/#{project_id}/w")

      assert html =~ "Some banner text"
    end

    test "only users with MFA enabled can access workorders for a project with MFA requirement",
         %{
           conn: conn
         } do
      user = insert(:user, mfa_enabled: true, user_totp: build(:user_totp))
      conn = log_in_user(conn, user)

      project =
        insert(:project,
          requires_mfa: true,
          project_users: [%{user: user, role: :admin}]
        )

      {:ok, _view, html} =
        live_async(conn, Routes.project_run_index_path(conn, :index, project.id))

      assert html =~ "History"

      ~w(editor viewer admin)a
      |> Enum.each(fn role ->
        {conn, _user} = setup_project_user(conn, project, role)

        assert {:error, {:redirect, %{to: "/mfa_required"}}} =
                 live(
                   conn,
                   Routes.project_run_index_path(conn, :index, project.id)
                 )
      end)
    end

    test "sends each work order with its input, runs and steps, and their links",
         %{conn: conn, project: project} do
      {work_order, dataclip} = setup_work_order(project)
      [run] = work_order.runs
      [step] = run.steps

      {:ok, view, _html} = live_async(conn, ~p"/projects/#{project}/history")

      assert %{
               "workflowId" => workflow_id,
               "workflowName" => workflow_name,
               "dataclipId" => dataclip_id,
               "dataclipWiped" => false,
               "href" => href,
               "dataclipHref" => dataclip_href,
               "runs" => [
                 %{
                   "id" => run_id,
                   "href" => run_href,
                   "steps" => [
                     %{
                       "id" => step_id,
                       "jobName" => job_name,
                       "cloned" => false,
                       "inputWiped" => false,
                       "jobDeleted" => false,
                       "href" => step_href
                     }
                   ]
                 }
               ]
             } = row(view, work_order)

      assert workflow_id == work_order.workflow_id
      assert workflow_name == work_order.snapshot.name
      assert dataclip_id == dataclip.id
      assert run_id == run.id
      assert step_id == step.id
      assert job_name == step.job.name

      assert href ==
               ~p"/projects/#{project}/history?#{%{filters: %{workorder_id: work_order.id}}}"

      assert dataclip_href ==
               ~p"/projects/#{project}/dataclips/#{dataclip.id}/show"

      assert run_href == ~p"/projects/#{project}/runs/#{run.id}"
      assert step_href == ~p"/projects/#{project}/runs/#{run.id}?step=#{step.id}"
    end

    test "the workflow and inspect links pin the version the run executed", %{
      conn: conn,
      project: project,
      user: user
    } do
      {work_order, _dataclip} = setup_work_order(project)
      [run] = work_order.runs
      [step] = run.steps
      path = ~p"/projects/#{project}/history"

      # The current version needs no pin.
      {:ok, view, _html} = live_async(conn, path)

      %{"workflowHref" => href, "runs" => [%{"steps" => [step_row]}]} =
        row(view, work_order)

      assert href ==
               ~p"/projects/#{project}/w/#{work_order.workflow_id}?#{%{run: run.id}}"

      assert step_row["inspectHref"] ==
               ~p"/projects/#{project}/w/#{work_order.workflow_id}?#{%{run: run.id, panel: "editor", job: step.job_id}}" <>
                 "#log"

      Repo.update!(Ecto.Changeset.change(work_order.workflow, lock_version: 99))

      {:ok, view, _html} = live_async(conn, path)

      %{"workflowHref" => href, "runs" => [%{"steps" => [step_row]}]} =
        row(view, work_order)

      assert href =~ ~r/[?&]run=#{run.id}/
      assert href =~ ~r/[?&]v=#{work_order.snapshot.lock_version}/
      refute href =~ "as_run="
      assert step_row["inspectHref"] =~ ~r/[?&]v=#{step.snapshot.lock_version}/

      Lightning.Accounts.update_user_preferences(user, %{
        "experimental_features" => true
      })

      {:ok, view, _html} = live_async(conn, path)

      %{"workflowHref" => href, "runs" => [%{"steps" => [step_row]}]} =
        row(view, work_order)

      assert href =~ ~r/[?&]as_run=#{run.id}/
      refute href =~ ~r/[?&]v=/
      assert step_row["inspectHref"] =~ ~r/[?&]as_run=#{run.id}/
    end

    test "a step reused from an earlier run is marked cloned", %{
      conn: conn,
      project: project
    } do
      {work_order, dataclip} = setup_work_order(project)
      [run] = work_order.runs
      [step] = run.steps

      later_run =
        insert(:run,
          work_order: work_order,
          snapshot: work_order.snapshot,
          dataclip: dataclip,
          starting_job: step.job,
          inserted_at: DateTime.add(step.inserted_at, 60),
          steps: [step]
        )

      {:ok, view, _html} = live_async(conn, ~p"/projects/#{project}/history")

      runs = row(view, work_order)["runs"]

      assert %{"steps" => [%{"cloned" => true}]} =
               Enum.find(runs, &(&1["id"] == later_run.id))

      assert %{"steps" => [%{"cloned" => false}]} =
               Enum.find(runs, &(&1["id"] == run.id))
    end

    @tag role: :admin
    test "a wiped input is marked, with the data storage link for those who can change it",
         %{conn: conn, project: project} do
      %{triggers: [trigger], jobs: [job | _rest]} =
        workflow = insert(:simple_workflow, project: project)

      wiped_dataclip = insert(:dataclip, body: nil, wiped_at: DateTime.utc_now())
      {:ok, snapshot} = Workflows.Snapshot.create(workflow)

      work_order =
        insert(:workorder,
          workflow: workflow,
          snapshot: snapshot,
          trigger: trigger,
          dataclip: wiped_dataclip,
          state: :failed,
          last_activity: DateTime.utc_now()
        )
        |> with_run(
          state: :failed,
          dataclip: wiped_dataclip,
          starting_trigger: trigger,
          finished_at: build(:timestamp),
          steps: [
            build(:step,
              finished_at: DateTime.utc_now(),
              job: job,
              exit_reason: "success",
              input_dataclip: nil,
              snapshot: snapshot,
              output_dataclip: nil
            ),
            build(:step,
              finished_at: DateTime.utc_now(),
              job: job,
              exit_reason: "success",
              input_dataclip: wiped_dataclip,
              snapshot: snapshot,
              output_dataclip: nil
            )
          ]
        )

      {:ok, view, _html} = live_async(conn, ~p"/projects/#{project}/history")

      assert %{
               "dataclipWiped" => true,
               "runs" => [%{"steps" => [unsaved, wiped]}]
             } = row(view, work_order)

      # Neither input can be rerun: one was never saved, the other was wiped.
      assert unsaved["inputWiped"]
      assert wiped["inputWiped"]

      assert page_props(view, @page)["dataStorageHref"] ==
               ~p"/projects/#{project}/settings#data-storage"
    end

    @tag role: :viewer
    test "the data storage link is left out for those who can't change it", %{
      conn: conn,
      project: project
    } do
      {:ok, view, _html} = live_async(conn, ~p"/projects/#{project}/history")

      assert %{"dataStorageHref" => nil, "canRunWorkflow" => false} =
               page_props(view, @page)
    end

    test "sends every run, newest first, with the time its state began", %{
      conn: conn,
      project: project
    } do
      workflow = insert(:workflow, project: project, name: "my workflow")
      trigger = insert(:trigger, type: :webhook, workflow: workflow)
      job = insert(:job, workflow: workflow)
      dataclip = insert(:dataclip)

      {:ok, snapshot} = Workflows.Snapshot.create(workflow)

      runs_params = [
        %{state: :claimed, state_timestamp: build(:timestamp)},
        %{state: :started, state_timestamp: build(:timestamp)}
      ]

      {work_order, [run_1, run_2]} =
        setup_work_order_with_multiple_runs(
          workflow,
          snapshot,
          trigger,
          job,
          dataclip,
          runs_params
        )

      {:ok, view, _html} = live_async(conn, ~p"/projects/#{project}/history")

      assert [
               %{"id" => id_2, "state" => "started", "startedAt" => started_at},
               %{"id" => id_1, "state" => "claimed", "claimedAt" => claimed_at}
             ] = row(view, work_order)["runs"]

      assert {id_1, id_2} == {run_1.id, run_2.id}
      assert started_at == DateTime.to_iso8601(run_2.started_at)
      assert claimed_at == DateTime.to_iso8601(run_1.claimed_at)
    end

    test "lists all workorders", %{
      conn: conn,
      project: project
    } do
      workflow = insert(:workflow, project: project, name: "my workflow")
      trigger = insert(:trigger, type: :webhook, workflow: workflow)

      {:ok, snapshot} = Workflows.Snapshot.create(workflow)

      dataclip = insert(:dataclip)

      rejected =
        insert(:workorder,
          workflow: workflow,
          snapshot: snapshot,
          trigger: trigger,
          dataclip: dataclip,
          last_activity: DateTime.utc_now(),
          state: :rejected
        )

      pending =
        insert(:workorder,
          workflow: workflow,
          snapshot: snapshot,
          trigger: trigger,
          dataclip: dataclip,
          last_activity: DateTime.utc_now()
        )

      {:ok, view, html} = live_async(conn, ~p"/projects/#{project.id}/history")

      assert html =~ "History"

      assert %{"state" => "rejected", "workflowName" => "my workflow"} =
               row(view, rejected)

      assert %{"state" => "pending", "runs" => []} = row(view, pending)
    end
  end

  describe "Search and Filtering" do
    test "filtering rejected workorders returns only rejected workorders", %{
      conn: conn,
      project: project
    } do
      workflow = insert(:workflow, project: project)

      rejected_work_order =
        insert(:workorder,
          workflow: workflow,
          dataclip: build(:dataclip),
          state: :rejected
        )

      failed_work_order =
        insert(:workorder,
          workflow: workflow,
          dataclip: build(:dataclip),
          state: :failed
        )

      {:ok, view, _html} = live_async(conn, ~p"/projects/#{project}/history")

      assert Enum.sort(row_ids(view)) ==
               Enum.sort([failed_work_order.id, rejected_work_order.id])

      {:ok, view, _html} =
        live_async(
          conn,
          ~p"/projects/#{project}/history?#{%{filters: %{rejected: true}}}"
        )

      assert row_ids(view) == [rejected_work_order.id]

      {:ok, view, _html} =
        live_async(
          conn,
          ~p"/projects/#{project}/history?#{%{filters: %{failed: true}}}"
        )

      assert row_ids(view) == [failed_work_order.id]
    end

    test "starts by sending a loading search", %{
      conn: conn,
      project: project
    } do
      {:ok, _view, html} = live(conn, ~p"/projects/#{project}/history")

      props =
        html
        |> Floki.parse_document!()
        |> Floki.find(@page)
        |> Floki.attribute("data-props")
        |> List.first()
        |> Jason.decode!()

      assert %{"state" => "loading", "rows" => []} = props
    end

    test "Filter by log and dataclip_body", %{
      conn: conn,
      project: project
    } do
      workflow_one = insert(:workflow, project: project, name: "workflow 1")
      trigger_one = insert(:trigger, type: :webhook, workflow: workflow_one)

      job_one =
        insert(:job,
          workflow: workflow_one,
          body: ~s[fn(state => { return {...state, extra: "data"} })]
        )

      {:ok, snapshot_one} = Workflows.Snapshot.create(workflow_one)

      dataclip =
        insert(:dataclip,
          type: :http_request,
          body: %{"username" => "eliaswalyba"},
          project: project
        )

      %{runs: [run_one]} =
        work_order_for(trigger_one,
          workflow: workflow_one,
          snapshot: snapshot_one,
          dataclip: dataclip,
          runs: [
            build(:run,
              snapshot: snapshot_one,
              dataclip: dataclip,
              starting_trigger: trigger_one
            )
          ]
        )
        |> insert()

      expected_d1 = Timex.now() |> Timex.shift(days: -12)

      {:ok, _step} =
        Runs.start_step(run_one, %{
          "job_id" => job_one.id,
          "input_dataclip_id" => dataclip.id,
          "started_at" => expected_d1,
          "finished_at" => expected_d1 |> Timex.shift(minutes: 2),
          "step_id" => Ecto.UUID.generate()
        })

      workflow_two = insert(:workflow, project: project, name: "workflow 2")
      trigger_two = insert(:trigger, type: :webhook, workflow: workflow_two)
      job_two = insert(:job, workflow: workflow_two)

      {:ok, snapshot_two} = Workflows.Snapshot.create(workflow_two)

      dataclip =
        insert(:dataclip,
          type: :http_request,
          body: %{"username" => "qassim"},
          project: project
        )

      work_order_two =
        insert(:workorder,
          workflow: workflow_two,
          trigger: trigger_two,
          dataclip: dataclip,
          snapshot: snapshot_two,
          last_activity: DateTime.utc_now(),
          state: :failed
        )

      run_two =
        insert(:run,
          work_order: work_order_two,
          dataclip: dataclip,
          starting_trigger: trigger_two,
          snapshot: snapshot_two
        )

      expected_d2 = Timex.now() |> Timex.shift(days: -10)

      {:ok, _step} =
        Runs.start_step(run_two, %{
          "job_id" => job_two.id,
          "input_dataclip_id" => dataclip.id,
          "started_at" => expected_d2,
          "finished_at" => expected_d2 |> Timex.shift(minutes: 5),
          "log_lines" => [
            %{body: "Hi mom!"},
            %{body: "Log me something fun."},
            %{body: "It's another great log."}
          ],
          "step_id" => Ecto.UUID.generate()
        })

      flush_dataclip_search_index()

      search = fn term, fields ->
        filters =
          Map.new(fields, &{&1, true}) |> Map.put(:search_term, term)

        {:ok, view, _html} =
          live_async(
            conn,
            ~p"/projects/#{project}/history?#{%{filters: filters}}"
          )

        Enum.map(rows(view), & &1["workflowName"])
      end

      assert search.("xxxx", [:log]) == []
      assert search.("eliaswalyba", [:body, :log]) == ["workflow 1"]
      assert search.("qassim", [:body, :log]) == ["workflow 2"]
      assert search.("some log", [:body]) == []
      assert search.("some log", [:log]) == []
    end
  end

  describe "Show" do
    test "no access to project on show", %{conn: conn, project: project} do
      workflow =
        %{triggers: [trigger]} = insert(:simple_workflow, project: project)

      run =
        build(:run, dataclip: insert(:dataclip), starting_trigger: trigger)

      insert(:workorder, workflow: workflow)
      |> with_run(run)

      {:ok, view, _html} =
        live(conn, ~p"/projects/#{project}/runs/#{run}")

      assert view |> render_async() =~ run.id

      project = insert(:project)

      workflow =
        %{triggers: [trigger]} = insert(:simple_workflow, project: project)

      run =
        build(:run, dataclip: insert(:dataclip), starting_trigger: trigger)

      insert(:workorder, workflow: workflow)
      |> with_run(run)

      error =
        live(conn, ~p"/projects/#{project}/runs/#{run}")

      assert error ==
               {:error,
                {:redirect, %{flash: %{"nav" => :not_found}, to: "/projects"}}}
    end
  end

  describe "handle_async/3" do
    test "a search that fails reaches the page as an error", %{
      conn: conn,
      project: project
    } do
      # SearchParams raises on a sort it doesn't know, inside the search task.
      {{:ok, view, _html}, _log} =
        with_log(fn ->
          live_async(
            conn,
            ~p"/projects/#{project}/history?#{%{filters: %{sort_by: "nope"}}}"
          )
        end)

      assert %{"state" => "error", "rows" => []} = page_props(view, @page)
    end
  end

  describe "handle_info/2" do
    test "WorkOrders.Events.RunCreated", %{
      conn: conn,
      project: project
    } do
      workflow = insert(:workflow, project: project)
      trigger = insert(:trigger, type: :webhook, workflow: workflow)
      job = insert(:job, workflow: workflow)

      dataclip = insert(:dataclip)

      work_order =
        work_order_for(trigger,
          workflow: workflow,
          dataclip: dataclip,
          last_activity: DateTime.utc_now()
        )
        |> insert()

      {:ok, view, _html} =
        live_async(conn, Routes.project_run_index_path(conn, :index, project.id))

      run =
        insert(:run,
          work_order: work_order,
          dataclip: dataclip,
          starting_job: job
        )

      run_ids = fn -> Enum.map(row(view, work_order)["runs"], & &1["id"]) end

      refute run.id in run_ids.()

      Events.run_created(project.id, run)

      # Force Re-render to ensure the event is included
      render(view)

      assert run.id in run_ids.()
    end

    test "WorkOrders.Events.RunUpdated", %{
      conn: conn,
      project: project
    } do
      workflow = insert(:workflow, project: project)
      trigger = insert(:trigger, type: :webhook, workflow: workflow)
      job_1 = insert(:job, workflow: workflow)
      job_2 = insert(:job, workflow: workflow)

      {:ok, snapshot} = Workflows.Snapshot.create(workflow)

      dataclip = insert(:dataclip)

      work_order =
        insert(:workorder,
          workflow: workflow,
          snapshot: snapshot,
          trigger: trigger,
          dataclip: dataclip,
          last_activity: DateTime.utc_now()
        )

      run =
        insert(:run,
          work_order: work_order,
          snapshot: snapshot,
          dataclip: dataclip,
          starting_trigger: trigger
        )

      step_1 =
        insert(:step,
          job: job_1,
          runs: [run],
          snapshot: snapshot,
          exit_reason: "success",
          started_at: build(:timestamp),
          finished_at: build(:timestamp)
        )

      {:ok, view, _html} =
        live_async(conn, Routes.project_run_index_path(conn, :index, project.id))

      step_2 =
        insert(:step,
          job: job_2,
          runs: [run],
          snapshot: snapshot,
          exit_reason: "success",
          started_at: build(:timestamp),
          finished_at: build(:timestamp)
        )

      step_ids = fn ->
        [%{"steps" => steps}] = row(view, work_order)["runs"]
        Enum.map(steps, & &1["id"])
      end

      assert step_ids.() == [step_1.id]

      Events.run_updated(project.id, run)

      # Force Re-render to ensure the event is included
      render(view)

      assert Enum.sort(step_ids.()) == Enum.sort([step_1.id, step_2.id])
    end

    test "WorkOrders.Events.WorkOrderCreated", %{
      conn: conn,
      project: project
    } do
      workflow_1 = insert(:workflow, project: project)
      trigger_1 = insert(:trigger, type: :webhook, workflow: workflow_1)
      job_1 = insert(:job, workflow: workflow_1)
      dataclip_1 = insert(:dataclip, project: project)

      workflow_2 = insert(:workflow, project: project)
      trigger_2 = insert(:trigger, type: :webhook, workflow: workflow_2)
      job_2 = insert(:job, workflow: workflow_2)
      dataclip_2 = insert(:dataclip, project: project)
      {:ok, snapshot_1} = Workflows.Snapshot.create(workflow_1)
      {:ok, snapshot_2} = Workflows.Snapshot.create(workflow_2)

      # filter by workflow
      {:ok, view, _html} =
        live_async(
          conn,
          Routes.project_run_index_path(conn, :index, project.id,
            filters: %{workflow_id: workflow_1.id}
          )
        )

      work_order_1 =
        insert(:workorder,
          workflow: workflow_1,
          trigger: trigger_1,
          dataclip: dataclip_1,
          runs: [
            build(:run,
              dataclip: dataclip_1,
              starting_trigger: trigger_1,
              steps: [
                build(:step,
                  job: job_1,
                  snapshot: snapshot_1,
                  exit_reason: "success",
                  started_at: build(:timestamp),
                  finished_at: build(:timestamp)
                )
              ]
            )
          ]
        )

      work_order_2 =
        insert(:workorder,
          workflow: workflow_2,
          trigger: trigger_2,
          dataclip: dataclip_2,
          runs: [
            build(:run,
              dataclip: dataclip_2,
              starting_trigger: trigger_2,
              steps: [
                build(:step,
                  job: job_2,
                  snapshot: snapshot_2,
                  exit_reason: "success",
                  started_at: build(:timestamp),
                  finished_at: build(:timestamp)
                )
              ]
            )
          ]
        )

      assert row_ids(view) == []

      Events.subscribe(project.id)

      # send a workorder that matches the current filter criteria
      Events.work_order_created(project.id, work_order_1)
      %{id: wo_id} = work_order_1
      assert_received %Events.WorkOrderCreated{work_order: %{id: ^wo_id}}

      # Awaits for async changes and forces re-render
      render_async(view)
      render(view)

      assert row_ids(view) == [work_order_1.id]

      # repeat same test for another workorder and show that it does not appear
      Events.work_order_created(project.id, work_order_2)
      %{id: wo_id} = work_order_2
      assert_received %Events.WorkOrderCreated{work_order: %{id: ^wo_id}}

      render(view)

      assert row_ids(view) == [work_order_1.id]
    end
  end
end
