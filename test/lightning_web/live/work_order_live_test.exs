defmodule LightningWeb.WorkOrderLiveTest do
  use LightningWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Lightning.Factories
  import Lightning.ApplicationHelpers, only: [dynamically_absorb_delay: 1]

  alias Lightning.Runs
  alias Lightning.WorkOrders.Events
  alias Lightning.WorkOrders.SearchParams
  alias Lightning.Workflows

  alias LightningWeb.LiveHelpers

  alias Phoenix.LiveView.AsyncResult

  import Lightning.Factories

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

  defp format_timestamp(timestamp) do
    Calendar.strftime(timestamp, "%Y-%m-%d %H:%M:%S.%f UTC")
    |> String.replace(~r/\.(\d{3})\d+/, ".\\1")
  end

  defp assert_work_order_steps(work_order, expected_count) do
    assert length(work_order.runs) === expected_count

    steps_count =
      work_order.runs
      |> Enum.map(&Map.get(&1, :steps, []))
      |> Enum.flat_map(& &1)
      |> length()

    assert steps_count === expected_count
  end

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

    test "WorkOrderComponent renders correctly with valid data", %{
      project: project
    } do
      {work_order, _dataclip} = setup_work_order(project)

      assert_work_order_steps(work_order, 1)

      rendered =
        render_component(LightningWeb.RunLive.WorkOrderComponent,
          id: work_order.id,
          work_order: work_order,
          project: project,
          can_run_workflow: true,
          can_edit_data_retention: true
        )

      assert rendered =~ work_order.dataclip_id
      assert rendered =~ "toggle_details_for_#{work_order.id}"
    end

    test "WorkOrderComponent renders steps when details are toggled", %{
      project: project
    } do
      {work_order, _dataclip} = setup_work_order(project)

      assert_work_order_steps(work_order, 1)

      rendered =
        render_component(LightningWeb.RunLive.WorkOrderComponent,
          id: work_order.id,
          work_order: work_order,
          show_details: true,
          project: project,
          can_run_workflow: true,
          can_run_workflow: true,
          can_edit_data_retention: true
        )

      assert rendered =~ work_order.dataclip_id
      assert rendered =~ "toggle_details_for_#{work_order.id}"

      work_order.runs
      |> Enum.each(fn run ->
        assert rendered =~ "run_#{run.id}"
      end)

      hd(work_order.runs).steps
      |> Enum.each(fn step ->
        assert rendered =~ "step-#{step.id}"
      end)
    end

    test "WorkOrderComponent disables dataclip link if the dataclip has been wiped",
         %{
           project: project
         } do
      %{triggers: [trigger], jobs: [job | _rest]} =
        workflow = insert(:simple_workflow, project: project)

      wiped_dataclip = insert(:dataclip, body: nil, wiped_at: DateTime.utc_now())

      work_order =
        work_order_for(trigger,
          workflow: workflow,
          dataclip: wiped_dataclip,
          state: :failed,
          runs: [
            build(:run,
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
                  output_dataclip: nil
                )
              ]
            )
          ]
        )
        |> insert()
        |> Repo.preload(runs: :steps)

      html =
        render_component(LightningWeb.RunLive.WorkOrderComponent,
          id: work_order.id,
          work_order: work_order,
          project: project,
          can_run_workflow: true,
          can_edit_data_retention: true
        )

      parsed_html = Floki.parse_fragment!(html)

      refute parsed_html
             |> Floki.find(
               ~s{a#view-dataclip-#{wiped_dataclip.id}-for-#{work_order.id}}
             )
             |> Enum.any?(),
             "dataclip link not available"

      assert parsed_html
             |> Floki.find(
               ~s{span#view-dataclip-#{wiped_dataclip.id}-for-#{work_order.id}}
             )
             |> Enum.any?()

      dataclip_element =
        parsed_html
        |> Floki.find(
          ~s{span#view-dataclip-#{wiped_dataclip.id}-for-#{work_order.id}}
        )
        |> hd()

      dataclip_html = Floki.raw_html(dataclip_element)

      assert dataclip_html =~ "The input dataclip is unavailable"

      assert dataclip_html =~ "Go to data storage settings",
             "User sees link to go to settings"

      refute dataclip_html =~ "contact one of your project admins"

      # User cannot edit data retention

      html =
        render_component(LightningWeb.RunLive.WorkOrderComponent,
          id: work_order.id,
          work_order: work_order,
          project: project,
          can_run_workflow: true,
          can_edit_data_retention: false
        )

      parsed_html = Floki.parse_fragment!(html)

      refute parsed_html
             |> Floki.find(
               ~s{a#view-dataclip-#{wiped_dataclip.id}-for-#{work_order.id}}
             )
             |> Enum.any?(),
             "dataclip link not available"

      assert parsed_html
             |> Floki.find(
               ~s{span#view-dataclip-#{wiped_dataclip.id}-for-#{work_order.id}}
             )
             |> Enum.any?()

      dataclip_html =
        parsed_html
        |> Floki.find(
          ~s{span#view-dataclip-#{wiped_dataclip.id}-for-#{work_order.id}}
        )
        |> hd()
        |> Floki.raw_html()

      assert dataclip_html =~ "The input dataclip is unavailable"

      refute dataclip_html =~ "Go to data storage settings",
             "User cannot see link to go to settings"

      assert dataclip_html =~ "contact one of your project admins"

      # Normal dataclip

      parsed_html =
        render_component(LightningWeb.RunLive.WorkOrderComponent,
          id: work_order.id,
          work_order: %{work_order | dataclip: insert(:dataclip)},
          project: project,
          can_run_workflow: true,
          can_edit_data_retention: false
        )
        |> Floki.parse_fragment!()

      assert parsed_html
             |> Floki.find(
               ~s{a#view-dataclip-#{wiped_dataclip.id}-for-#{work_order.id}}
             )
             |> Enum.any?(),
             "dataclip link available"
    end

    test "WorkOrderComponent disables the select checkbox if the dataclip has been wiped",
         %{
           project: project
         } do
      %{triggers: [trigger], jobs: [job | _rest]} =
        workflow = insert(:simple_workflow, project: project)

      wiped_dataclip = insert(:dataclip, body: nil, wiped_at: DateTime.utc_now())

      work_order =
        work_order_for(trigger,
          workflow: workflow,
          dataclip: wiped_dataclip,
          state: :failed,
          runs: [
            build(:run,
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
                  output_dataclip: nil
                )
              ]
            )
          ]
        )
        |> insert()
        |> Repo.preload(runs: :steps)

      html =
        render_component(LightningWeb.RunLive.WorkOrderComponent,
          id: work_order.id,
          work_order: work_order,
          project: project,
          can_run_workflow: true,
          can_edit_data_retention: true
        )

      parsed_html = Floki.parse_fragment!(html)

      assert parsed_html
             |> Floki.find(~s{form#selection-form-#{work_order.id}})
             |> Enum.any?(),
             "selection form exists"

      refute parsed_html
             |> Floki.find(
               ~s{form#selection-form-#{work_order.id}[phx-change="toggle_selection"]}
             )
             |> Enum.any?(),
             "selection form does not have the phx-change attr"

      tooltip_html =
        parsed_html
        |> Floki.find(~s{form #select_#{work_order.id}_tooltip})
        |> hd()
        |> Floki.raw_html()

      assert tooltip_html =~
               "This work order cannot be rerun since no input data has been stored"

      assert tooltip_html =~ "Go to data storage settings",
             "User sees link to go to settings"

      refute tooltip_html =~ "contact one of your project admins"

      # User cannot edit data retention

      html =
        render_component(LightningWeb.RunLive.WorkOrderComponent,
          id: work_order.id,
          work_order: work_order,
          project: project,
          can_run_workflow: true,
          can_edit_data_retention: false
        )

      parsed_html = Floki.parse_fragment!(html)

      assert parsed_html
             |> Floki.find(~s{form#selection-form-#{work_order.id}})
             |> Enum.any?(),
             "selection form exists"

      refute parsed_html
             |> Floki.find(
               ~s{form#selection-form-#{work_order.id}[phx-change="toggle_selection"]}
             )
             |> Enum.any?(),
             "selection form does not have the phx-change attr"

      tooltip_html =
        parsed_html
        |> Floki.find(~s{form #select_#{work_order.id}_tooltip})
        |> hd()
        |> Floki.raw_html()

      assert tooltip_html =~
               "This work order cannot be rerun since no input data has been stored"

      refute tooltip_html =~ "Go to data storage settings",
             "User cannot see link to go to settings"

      assert tooltip_html =~ "contact one of your project admins"

      # Normal dataclip

      parsed_html =
        render_component(LightningWeb.RunLive.WorkOrderComponent,
          id: work_order.id,
          work_order: %{work_order | dataclip: insert(:dataclip)},
          project: project,
          can_run_workflow: true,
          can_edit_data_retention: false
        )
        |> Floki.parse_fragment!()

      assert parsed_html
             |> Floki.find(
               ~s{form#selection-form-#{work_order.id}[phx-change="toggle_selection"]}
             )
             |> Enum.any?()

      refute parsed_html
             |> Floki.find(~s{form #select_#{work_order.id}_tooltip})
             |> Enum.any?(),
             "tooltip does not exist"
    end

    test "toggle details of a work order shows attempt state and timestamp", %{
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

      claimed_at_formatted = format_timestamp(run_1.claimed_at)
      claimed_at = DateTime.to_iso8601(run_1.claimed_at)

      started_at_formatted = format_timestamp(run_2.started_at)
      started_at = DateTime.to_iso8601(run_2.started_at)

      {:ok, view, _html} =
        live_async(conn, Routes.project_run_index_path(conn, :index, project.id))

      rendered =
        view |> element("#toggle_details_for_#{work_order.id}") |> render_click()

      assert rendered =~ run_2.id
      refute rendered =~ run_1.id

      assert view
             |> element("#toggle_runs_for_#{work_order.id}")
             |> render_click() =~ run_1.id

      claimed_at_element =
        view
        |> element("div[data-label='run state']", "claimed")
        |> render()

      assert claimed_at_element =~ claimed_at

      assert claimed_at_element =~
               "data-iso-timestamp=\"#{claimed_at_formatted}\""

      started_at_element =
        view
        |> element("div[data-label='run state']", "started")
        |> render()

      assert started_at_element =~ started_at

      assert started_at_element =~
               "data-iso-timestamp=\"#{started_at_formatted}\""
    end

    test "lists all workorders", %{
      conn: conn,
      project: project
    } do
      workflow = insert(:workflow, project: project, name: "my workflow")
      trigger = insert(:trigger, type: :webhook, workflow: workflow)
      job = insert(:job, workflow: workflow)

      {:ok, snapshot} = Workflows.Snapshot.create(workflow)

      dataclip = insert(:dataclip)

      insert(:workorder,
        workflow: workflow,
        snapshot: snapshot,
        trigger: trigger,
        dataclip: dataclip,
        last_activity: DateTime.utc_now(),
        state: :rejected
      )

      work_order =
        insert(:workorder,
          workflow: workflow,
          snapshot: snapshot,
          trigger: trigger,
          dataclip: dataclip,
          last_activity: DateTime.utc_now()
        )

      %{id: run_id} =
        insert(:run,
          work_order: work_order,
          snapshot: snapshot,
          starting_trigger: trigger,
          dataclip: dataclip,
          finished_at: build(:timestamp),
          steps: [
            build(:step,
              job: job,
              snapshot: snapshot,
              started_at: build(:timestamp),
              finished_at: build(:timestamp),
              exit_reason: "fail",
              input_dataclip: dataclip
            )
          ]
        )

      {:ok, view, html} =
        live_async(conn, ~p"/projects/#{project.id}/history")

      assert html =~ "History"

      table =
        view
        |> element("#work-orders-table")
        |> render()

      assert table =~ workflow.name
      assert table =~ LiveHelpers.display_short_uuid(work_order.id)
      assert table =~ LiveHelpers.display_short_uuid(dataclip.id)

      refute has_element?(view, "#run_#{run_id}")

      # Check both work orders exist and have correct states
      # The first work order has state: :rejected
      # The second work order (work_order variable) has default state: :pending

      # Since we don't have the ID of the first work order, we need to check that both states exist
      # We can check that the table contains both "Rejected" and "Pending" statuses
      table_html =
        view
        |> element("#work-orders-table")
        |> render()

      assert table_html =~ "Rejected"
      assert table_html =~ "Enqueued"

      # toggle work_order details
      # TODO move to test work_order_component

      expanded =
        view
        |> element(
          "tbody#workorder-#{work_order.id} tr#toggle_details_for_#{work_order.id}"
        )
        |> render_click()

      assert expanded =~ "run-#{run_id}"
      assert expanded =~ LiveHelpers.display_short_uuid(run_id)

      collapsed_again =
        view
        |> element(
          "tbody#workorder-#{work_order.id} tr#toggle_details_for_#{work_order.id}"
        )
        |> render_click()

      refute collapsed_again =~ "run-#{run_id}"
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

      {:ok, view, _html} =
        live_async(conn, ~p"/projects/#{project}/history")

      [failed_work_order, rejected_work_order]
      |> Enum.each(fn %{id: id} ->
        assert view |> has_element?("#workorder-#{id}")
      end)

      view
      |> form("#workorder-filter-form",
        filters: %{"rejected" => "true", "failed" => "false"}
      )
      |> render_submit()

      refute view |> has_element?("#workorder-#{failed_work_order.id}")

      dynamically_absorb_delay(fn ->
        view |> has_element?("#workorder-#{rejected_work_order.id}")
      end)

      assert view |> has_element?("#workorder-#{rejected_work_order.id}")

      view
      |> form("#workorder-filter-form",
        filters: %{"rejected" => "false", "failed" => "true"}
      )
      |> render_submit()

      dynamically_absorb_delay(fn ->
        view |> has_element?("#workorder-#{failed_work_order.id}")
      end)

      assert view |> has_element?("#workorder-#{failed_work_order.id}")
      refute view |> has_element?("#workorder-#{rejected_work_order.id}")
    end

    test "starts by rendering an animated loading of work orders", %{
      conn: conn,
      project: project
    } do
      workflow = insert(:workflow, project: project)
      trigger = insert(:trigger, type: :webhook, workflow: workflow)
      job = insert(:job, workflow: workflow)

      dataclip = insert(:dataclip)

      {:ok, snapshot} = Lightning.Workflows.Snapshot.create(workflow)

      work_order =
        insert(:workorder,
          workflow: workflow,
          trigger: trigger,
          dataclip: dataclip,
          snapshot: snapshot
        )

      run =
        insert(:run,
          work_order: work_order,
          dataclip: dataclip,
          starting_trigger: trigger,
          snapshot: snapshot
        )

      {:ok, _step} =
        Runs.start_step(run, %{
          "job_id" => job.id,
          "input_dataclip_id" => dataclip.id,
          "step_id" => Ecto.UUID.generate()
        })

      {:ok, _view, html} =
        live(conn, Routes.project_run_index_path(conn, :index, project.id))

      # render element is flaky due to async so it parses the html
      work_order_list =
        html
        |> Floki.parse_fragment!()
        |> Floki.find("#work-orders-table tbody > tr:first-child")
        |> hd()

      assert Floki.children(work_order_list) |> Floki.text() =~
               "Loading work orders ..."
    end

    test "Search form is displayed", %{conn: conn, project: project} do
      {:ok, view, html} =
        live_async(conn, Routes.project_run_index_path(conn, :index, project.id))

      assert html =~ "Status"

      status_filters = [
        "rejected",
        "success",
        "failed",
        "running",
        "crashed",
        "pending",
        "killed",
        "failed"
      ]

      assert status_filters
             |> Enum.all?(fn f ->
               input_selector =
                 "input[name='#{Phoenix.HTML.Form.input_name(:filters, f)}']"

               view
               |> element("#workorder-filter-form #{input_selector}")
               |> has_element?()
             end)

      assert status_filters
             |> Enum.any?(fn f ->
               view
               |> element(
                 "#workorder-filter-form input[name='#{Phoenix.HTML.Form.input_name(:filters, f)}'][checked]"
               )
               |> has_element?()
             end) == false

      assert view
             |> element(
               "form#run-search-form input[name='#{Phoenix.HTML.Form.input_name(:filters, :search_term)}']"
             )
             |> has_element?()

      ## id, log and body select
      assert view
             |> element(
               "input#run-toggle-form_body[type='checkbox'][value='true']"
             )
             |> has_element?()

      assert view
             |> element(
               "input#run-toggle-form_log[type='checkbox'][value='true']"
             )
             |> has_element?()

      assert view
             |> element(
               "input#run-toggle-form_id[type='checkbox'][value='true']"
             )
             |> has_element?()
    end

    test "Work Order with failed status shows when option checked", %{
      conn: conn,
      project: project
    } do
      workflow = insert(:workflow, project: project)
      trigger = insert(:trigger, type: :webhook, workflow: workflow)
      job = insert(:job, workflow: workflow)

      dataclip = insert(:dataclip)

      {:ok, snapshot} = Lightning.Workflows.Snapshot.create(workflow)

      work_order =
        insert(:workorder,
          workflow: workflow,
          trigger: trigger,
          dataclip: dataclip,
          snapshot: snapshot,
          last_activity: DateTime.utc_now(),
          state: :failed
        )

      run =
        insert(:run,
          work_order: work_order,
          dataclip: dataclip,
          starting_trigger: trigger,
          snapshot: snapshot
        )

      {:ok, _step} =
        Runs.start_step(run, %{
          "job_id" => job.id,
          "input_dataclip_id" => dataclip.id,
          "step_id" => Ecto.UUID.generate()
        })

      {:ok, view, _html} =
        live_async(conn, Routes.project_run_index_path(conn, :index, project.id))

      assert view
             |> element(
               "tbody#workorder-#{work_order.id} td.text-right:nth-child(8)"
             )
             |> render() =~ "Failed"

      # uncheck :failure
      view
      |> form("#workorder-filter-form", filters: %{"failed" => "false"})
      |> render_submit()

      refute view
             |> element("tbody#workorder-#{work_order.id}")
             |> has_element?()

      # recheck failure

      view
      |> form("#workorder-filter-form", filters: %{"failed" => "true"})
      |> render_submit()

      div =
        view
        |> element("tbody#workorder-#{work_order.id} td.text-right:nth-child(8)")
        |> render_async()

      assert div =~ "Failed"
    end

    test "Filter by workflow", %{
      conn: conn,
      project: project
    } do
      workflow = insert(:workflow, project: project, name: "workflow 1")
      trigger = insert(:trigger, type: :webhook, workflow: workflow)

      job =
        insert(:job,
          workflow: workflow,
          body: ~s[fn(state => { return {...state, extra: "data"} })]
        )

      {:ok, snapshot} = Lightning.Workflows.Snapshot.create(workflow)

      dataclip = insert(:dataclip)

      insert(:workorder,
        workflow: workflow,
        trigger: trigger,
        dataclip: dataclip,
        snapshot: snapshot,
        last_activity: DateTime.utc_now(),
        runs: [
          build(:run,
            starting_trigger: trigger,
            dataclip: dataclip,
            snapshot: snapshot,
            steps: [
              build(:step,
                job: job,
                snapshot: snapshot,
                input_dataclip: dataclip,
                started_at: build(:timestamp),
                finished_at: build(:timestamp),
                exit_reason: "success"
              )
            ]
          )
        ]
      )

      workflow_two = insert(:workflow, project: project, name: "workflow 2")
      trigger_two = insert(:trigger, type: :webhook, workflow: workflow_two)

      job_two =
        insert(:job,
          workflow: workflow_two,
          body: ~s[fn(state => { return {...state, extra: "data"} })]
        )

      {:ok, snapshot_two} = Lightning.Workflows.Snapshot.create(workflow_two)

      dataclip_two = insert(:dataclip)

      insert(:workorder,
        workflow: workflow_two,
        trigger: trigger_two,
        dataclip: dataclip_two,
        snapshot: snapshot_two,
        last_activity: DateTime.utc_now(),
        runs: [
          build(:run,
            starting_trigger: trigger_two,
            dataclip: dataclip_two,
            snapshot: snapshot_two,
            steps: [
              build(:step,
                job: job_two,
                snapshot: snapshot_two,
                input_dataclip: dataclip_two,
                started_at: build(:timestamp),
                finished_at: build(:timestamp),
                exit_reason: "failed"
              )
            ]
          )
        ]
      )

      job_other_project =
        insert(:job,
          body: ~s[fn(state => { return {...state, extra: "data"} })],
          workflow:
            insert(:workflow, name: "my workflow", project: insert(:project))
        )

      {:ok, view, html} =
        live(conn, Routes.project_run_index_path(conn, :index, project.id))

      assert html =~ "Workflow"

      assert has_workflow_in_dropdown?(view, job.workflow_id)

      refute has_workflow_in_dropdown?(view, job_other_project.workflow_id)

      assert has_workflow_in_dropdown?(view, job_two.workflow_id)
      select_workflow_in_dropdown(view, job_two.workflow_id)

      div =
        view
        |> element("tbody:first-child")
        |> render_async()

      refute div =~ "workflow 1"
      assert div =~ "workflow 2"

      select_workflow_in_dropdown(view, job.workflow_id)

      div =
        view
        |> element("tbody:first-child")
        |> render_async()

      assert div =~ "workflow 1"
      refute div =~ "workflow 2"
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
          body: %{"username" => "eliaswalyba"}
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
        insert(:dataclip, type: :http_request, body: %{"username" => "qassim"})

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

      {:ok, view, _html} =
        live_async(conn, Routes.project_run_index_path(conn, :index, project.id))

      div =
        view
        |> element("tbody:first-child td.text-right:nth-child(8)")
        |> render()

      assert div =~ "Failed"

      view |> search_for("xxxx", [])

      refute workflow_displayed(view, "workflow 1")
      refute workflow_displayed(view, "workflow 2")

      view
      |> search_for("xxxx", [:log])

      refute workflow_displayed(view, "workflow 1")
      refute workflow_displayed(view, "workflow 2")

      view
      |> form("#run-toggle-form", filters: %{"body" => "true"})
      |> render_change()

      view
      |> search_for("eliaswalyba", [:body, :log])

      assert workflow_displayed(view, "workflow 1")
      refute workflow_displayed(view, "workflow 2")

      view |> search_for("qassim", [:body, :log])

      refute workflow_displayed(view, "workflow 1")
      assert workflow_displayed(view, "workflow 2")

      view |> search_for("some log", [:body])

      refute workflow_displayed(view, "workflow 1")
      refute workflow_displayed(view, "workflow 2")

      view |> search_for("some log", [:log])

      refute workflow_displayed(view, "workflow 1")
      refute workflow_displayed(view, "workflow 2")
    end

    test "bulk select is disabled when there's no workorder matching the filter",
         %{
           conn: conn,
           project: project
         } do
      workflow = insert(:workflow, project: project, name: "workflow 1")
      trigger = insert(:trigger, type: :webhook, workflow: workflow)

      job =
        insert(:job,
          workflow: workflow,
          body: ~s[fn(state => { return {...state, extra: "data"} })]
        )

      dataclip = insert(:dataclip)

      insert(:workorder,
        workflow: workflow,
        trigger: trigger,
        dataclip: dataclip,
        last_activity: DateTime.utc_now(),
        runs: [
          build(:run,
            starting_trigger: trigger,
            dataclip: dataclip,
            steps: [
              build(:step,
                job: job,
                input_dataclip: dataclip,
                started_at: build(:timestamp),
                finished_at: build(:timestamp),
                exit_reason: "success"
              )
            ]
          )
        ]
      )

      workflow_two = insert(:workflow, project: project, name: "workflow 2")

      {:ok, view, _html} =
        live(conn, Routes.project_run_index_path(conn, :index, project.id))

      view |> select_workflow_in_dropdown(workflow.id)

      assert has_element?(view, "#select_all")
      refute has_element?(view, "#select_all:disabled")

      view |> select_workflow_in_dropdown(workflow_two.id)

      assert has_element?(view, "#select_all:disabled")
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

    test "by default only the latest run is present when there are multiple runs",
         %{conn: conn, user: user} do
      project =
        insert(:project,
          project_users: [%{role: :admin, user: user}]
        )

      workflow =
        insert(
          :workflow,
          %{
            name: "test workflow",
            project: project
          }
        )

      project_credential =
        insert(:project_credential,
          credential: %{
            name: "dummy",
            body: %{"test" => "dummy"}
          },
          project: project
        )

      job =
        insert(:job, %{
          body: "fn(state => state)",
          name: "some name",
          adaptor: "@openfn/language-common",
          workflow: workflow,
          project_credential: project_credential
        })

      trigger =
        insert(:trigger,
          workflow: workflow,
          type: :webhook
        )

      insert(:edge,
        workflow: workflow,
        source_trigger: trigger,
        target_job: job,
        condition_type: :always,
        enabled: true
      )

      dataclip = insert(:dataclip, project: project)

      work_order =
        insert(:workorder,
          workflow: workflow,
          trigger: trigger,
          dataclip: dataclip,
          last_activity: DateTime.utc_now(),
          state: :failed
        )

      run_1 =
        insert(:run,
          work_order: work_order,
          dataclip: dataclip,
          starting_trigger: trigger
        )

      run_2 =
        insert(:run,
          work_order: work_order,
          dataclip: dataclip,
          starting_trigger: trigger
        )

      {:ok, view, _html} =
        live_async(
          conn,
          Routes.project_run_index_path(conn, :index, project.id)
        )

      view |> element("#toggle_details_for_#{work_order.id}") |> render_click()

      refute has_element?(view, "#run_#{run_1.id}")
      assert has_element?(view, "#run_#{run_2.id}")
    end

    test "user can toggle to see all runs",
         %{conn: conn, user: user} do
      project =
        insert(:project,
          project_users: [%{role: :admin, user: user}]
        )

      workflow =
        insert(
          :workflow,
          %{
            name: "test workflow",
            project: project
          }
        )

      project_credential =
        insert(:project_credential,
          credential: %{
            name: "dummy",
            body: %{"test" => "dummy"}
          },
          project: project
        )

      job =
        insert(:job, %{
          body: "fn(state => state)",
          name: "some name",
          adaptor: "@openfn/language-common",
          workflow: workflow,
          project_credential: project_credential
        })

      trigger =
        insert(:trigger,
          workflow: workflow,
          type: :webhook
        )

      insert(:edge,
        workflow: workflow,
        source_trigger: trigger,
        target_job: job,
        condition_type: :always,
        enabled: true
      )

      dataclip = insert(:dataclip, project: project)

      {:ok, snapshot} = Workflows.Snapshot.create(workflow)

      workorder =
        insert(:workorder,
          state: :success,
          workflow: workflow,
          snapshot: snapshot,
          trigger: trigger,
          dataclip: dataclip,
          last_activity: DateTime.utc_now()
        )

      now = Timex.now()

      run_1 =
        insert(:run,
          work_order: workorder,
          snapshot: snapshot,
          state: :failed,
          starting_trigger: trigger,
          inserted_at: now |> Timex.shift(minutes: -5),
          dataclip: dataclip,
          steps:
            build_list(1, :step, %{
              job: job,
              snapshot: snapshot,
              exit_reason: "fail",
              started_at: now |> Timex.shift(seconds: -40),
              finished_at: now |> Timex.shift(seconds: -20),
              input_dataclip: dataclip
            })
        )

      run_2 =
        insert(:run,
          state: :success,
          work_order: workorder,
          snapshot: snapshot,
          starting_job: job,
          dataclip: dataclip,
          steps:
            build_list(1, :step,
              job: job,
              snapshot: snapshot,
              started_at: Timex.shift(now, seconds: -20),
              finished_at: now,
              input_dataclip: dataclip
            )
        )

      {:ok, view, _html} =
        live_async(
          conn,
          Routes.project_run_index_path(conn, :index, project.id)
        )

      view |> element("#toggle_details_for_#{workorder.id}") |> render_click()

      refute has_element?(view, "#run_#{run_1.id}")
      assert has_element?(view, "#run_#{run_2.id}")

      # show all
      view |> element("#toggle_runs_for_#{workorder.id}") |> render_click()
      assert has_element?(view, "#run_#{run_1.id}")
      assert has_element?(view, "#run_#{run_2.id}")

      # hide some
      view |> element("#toggle_runs_for_#{workorder.id}") |> render_click()
      refute has_element?(view, "#run_#{run_1.id}")
      assert has_element?(view, "#run_#{run_2.id}")
    end

    test "workorder row gets expanded by default if workorder_id is supplied in the filter",
         %{conn: conn, user: user} do
      project =
        insert(:project,
          project_users: [%{role: :admin, user: user}]
        )

      workflow = insert(:workflow, project: project)

      job =
        insert(:job, %{
          body: "fn(state => state)",
          name: "some name",
          adaptor: "@openfn/language-common",
          workflow: workflow,
          project_credential: nil
        })

      trigger =
        insert(:trigger,
          workflow: workflow,
          type: :webhook
        )

      insert(:edge,
        workflow: workflow,
        source_trigger: trigger,
        target_job: job,
        condition_type: :always,
        enabled: true
      )

      {:ok, snapshot} = Workflows.Snapshot.create(workflow)

      dataclip = insert(:dataclip, project: project)

      workorder =
        insert(:workorder,
          state: :success,
          workflow: workflow,
          snapshot: snapshot,
          trigger: trigger,
          dataclip: dataclip,
          last_activity: DateTime.utc_now()
        )

      run_1 =
        insert(:run,
          work_order: workorder,
          snapshot: snapshot,
          state: :failed,
          starting_trigger: trigger,
          inserted_at: build(:timestamp),
          dataclip: dataclip,
          steps:
            build_list(1, :step, %{
              job: job,
              snapshot: snapshot,
              exit_reason: "fail",
              started_at: build(:timestamp),
              finished_at: build(:timestamp),
              input_dataclip: dataclip
            })
        )

      run_2 =
        insert(:run,
          state: :success,
          work_order: workorder,
          snapshot: snapshot,
          starting_job: job,
          dataclip: dataclip,
          steps:
            build_list(1, :step,
              job: job,
              snapshot: snapshot,
              started_at: build(:timestamp),
              finished_at: build(:timestamp),
              input_dataclip: dataclip
            )
        )

      {:ok, view, _html} =
        live_async(
          conn,
          Routes.project_run_index_path(conn, :index, project.id)
        )

      # workorder is present
      assert has_element?(view, "#workorder-#{workorder.id}")

      # both runs are not present
      refute has_element?(view, "#run_#{run_1.id}")
      refute has_element?(view, "#run_#{run_2.id}")

      # lets add the workorder_id
      {:ok, view, _html} =
        live_async(
          conn,
          Routes.project_run_index_path(conn, :index, project.id,
            filters: %{workorder_id: workorder.id}
          )
        )

      # workorder is present
      assert has_element?(view, "#workorder-#{workorder.id}")

      # both runs are  present
      assert has_element?(view, "#run_#{run_1.id}")
      assert has_element?(view, "#run_#{run_2.id}")

      # both runs are visible
      refute has_element?(view, "#run_#{run_1.id}.hidden")
      refute has_element?(view, "#run_#{run_2.id}.hidden")
    end
  end

  describe "handle_async/3" do
    test "with exit error", %{conn: conn, project: project} do
      {:ok, view, _html} =
        live(conn, Routes.project_run_index_path(conn, :index, project.id))

      %{socket: socket} = :sys.get_state(view.pid)
      initial_async = AsyncResult.loading()

      assert {:noreply, %{assigns: assigns}} =
               LightningWeb.RunLive.Index.handle_async(
                 :load_workorders,
                 {:exit, "some reason"},
                 Map.merge(socket, %{
                   assigns: Map.put(socket.assigns, :async_page, initial_async)
                 })
               )

      assert %{page: %{total_pages: 0}, async_page: async_page} = assigns

      assert async_page ==
               AsyncResult.failed(initial_async, {:exit, "some reason"})
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
          dataclip: dataclip
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

      view |> element("#toggle_details_for_#{work_order.id}") |> render_click()

      refute has_element?(view, "#run_#{run.id}")

      Events.run_created(project.id, run)

      # Force Re-render to ensure the event is included
      render(view)

      assert has_element?(view, "#run_#{run.id}")
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
          dataclip: dataclip
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

      view |> element("#toggle_details_for_#{work_order.id}") |> render_click()

      assert has_element?(view, "#step-#{step_1.id}")
      refute has_element?(view, "#step-#{step_2.id}")

      Events.run_updated(project.id, run)

      # Force Re-render to ensure the event is included
      render(view)

      assert has_element?(view, "#step-#{step_1.id}")
      assert has_element?(view, "#step-#{step_2.id}")
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
                  exit_reason: "success",
                  started_at: build(:timestamp),
                  finished_at: build(:timestamp)
                )
              ]
            )
          ]
        )

      refute has_element?(view, "#workorder-#{work_order_1.id}")
      refute has_element?(view, "#workorder-#{work_order_2.id}")

      Events.subscribe(project.id)

      # send a workorder that matches the current filter criteria
      Events.work_order_created(project.id, work_order_1)
      %{id: wo_id} = work_order_1
      assert_received %Events.WorkOrderCreated{work_order: %{id: ^wo_id}}

      # Awaits for async changes and forces re-render
      render_async(view)
      render(view)

      assert has_element?(view, "#workorder-#{work_order_1.id}")

      # repeat same test for another workorder and show that it does not appear
      Events.work_order_created(project.id, work_order_2)
      %{id: wo_id} = work_order_2
      assert_received %Events.WorkOrderCreated{work_order: %{id: ^wo_id}}

      refute has_element?(view, "#workorder-#{work_order_2.id}")
    end
  end

  def search_for(view, term, types) when types == [] do
    search_for(view, term, [:log])
  end

  def search_for(view, term, types) do
    filter_attrs = %{"search_term" => term}

    for type <- [:body, :log] do
      checked = type in types
      Map.put(filter_attrs, "#{type}", "#{checked}")
    end

    view
    |> form("#run-search-form", filters: filter_attrs)
    |> render_submit()

    render_async(view)
  end

  def workflow_displayed(view, name) do
    elem =
      view
      |> element("tbody:first-child")

    if elem |> has_element?() do
      elem |> render() =~ name
    else
      false
    end
  end

  describe "rerun" do
    setup %{project: project} do
      workflow = insert(:workflow, project: project)
      trigger = insert(:trigger, type: :webhook, workflow: workflow)
      job_a = insert(:job, workflow: workflow)

      insert(:edge,
        workflow: workflow,
        source_trigger: trigger,
        target_job: job_a
      )

      dataclip = insert(:dataclip)

      work_order =
        insert(:workorder,
          workflow: workflow,
          trigger: trigger,
          dataclip: dataclip,
          last_activity: DateTime.utc_now()
        )

      run =
        insert(:run,
          work_order: work_order,
          state: :failed,
          dataclip: dataclip,
          starting_trigger: trigger,
          finished_at: build(:timestamp),
          steps: [
            build(:step,
              job: job_a,
              input_dataclip: dataclip,
              started_at: build(:timestamp),
              finished_at: build(:timestamp),
              exit_reason: "failed"
            )
          ]
        )

      %{run: run, work_order: work_order}
    end

    @tag role: :editor
    test "Project editors can rerun from a step",
         %{conn: conn, project: %{id: project_id}, run: run} do
      [step | _rest] = run.steps

      {:ok, view, _html} =
        live(conn, ~p"/projects/#{project_id}/history")

      assert view
             |> render_click("rerun", %{
               "run_id" => run.id,
               "step_id" => step.id
             })
    end

    @tag role: :editor
    test "Project editors can't rerun when limit has been reached",
         %{conn: conn, project: %{id: project_id}, run: run} do
      [step | _rest] = run.steps

      {:ok, view, _html} =
        live(conn, ~p"/projects/#{project_id}/history")

      Mox.stub(
        Lightning.Extensions.MockUsageLimiter,
        :limit_action,
        &Lightning.Extensions.StubUsageLimiter.limit_action/2
      )

      view
      |> render_click("rerun", %{
        "run_id" => run.id,
        "step_id" => step.id
      })

      assert view
             |> has_element?("[data-flash-kind='error']", "Runs limit exceeded")
    end

    @tag role: :viewer
    test "Project viewers can't rerun from steps",
         %{conn: conn, project: project, run: run} do
      [step | _rest] = run.steps

      {:ok, view, _html} =
        live(conn, Routes.project_run_index_path(conn, :index, project.id))

      assert view
             |> render_click("rerun", %{
               "run_id" => run.id,
               "step_id" => step.id
             }) =~
               "You are not authorized to perform this action."
    end

    @tag role: :viewer
    test "Project viewers can't rerun in bulk from start",
         %{conn: conn, project: project} do
      trigger = build(:trigger, type: :webhook)

      job_b =
        build(:job,
          body: ~s[fn(state => { return {...state, extra: "data"} })],
          name: "First Job"
        )

      workflow =
        build(:workflow, project: project)
        |> with_job(job_b)
        |> with_trigger(trigger)
        |> with_edge({trigger, job_b})
        |> insert()

      dataclip = insert(:dataclip, project: project)

      job_b = job_b |> Lightning.Repo.reload()
      trigger = trigger |> Lightning.Repo.reload()

      work_order_b =
        insert(:workorder,
          workflow: workflow,
          trigger: trigger,
          dataclip: dataclip
        )

      insert(:run,
        work_order: work_order_b,
        starting_trigger: trigger,
        dataclip: dataclip,
        finished_at: build(:timestamp),
        steps: [
          %{
            job: job_b,
            started_at: build(:timestamp),
            finished_at: build(:timestamp),
            exit_reason: "success",
            input_dataclip: dataclip
          }
        ]
      )

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

      assert render_click(view, "bulk-rerun", %{type: "all"}) =~
               "You are not authorized to perform this action."
    end

    @tag role: :editor
    test "Project editors can rerun in bulk from start",
         %{conn: conn, project: project} do
      trigger = build(:trigger, type: :webhook)

      job_b =
        build(:job,
          body: ~s[fn(state => { return {...state, extra: "data"} })],
          name: "First Job"
        )

      workflow =
        build(:workflow, project: project)
        |> with_job(job_b)
        |> with_trigger(trigger)
        |> with_edge({trigger, job_b})
        |> insert()

      job_b = workflow.jobs |> List.first()
      trigger = workflow.triggers |> List.first()

      dataclip = insert(:dataclip, project: project)

      other_4_work_orders =
        insert_list(4, :workorder,
          workflow: workflow,
          trigger: trigger,
          dataclip: dataclip,
          runs: [
            build(:run,
              id: nil,
              starting_trigger: trigger,
              dataclip: dataclip,
              finished_at: build(:timestamp),
              state: :success,
              steps: [
                %{
                  job: job_b,
                  started_at: build(:timestamp),
                  finished_at: build(:timestamp),
                  exit_reason: "success",
                  input_dataclip: dataclip
                }
              ]
            )
          ]
        )

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

      {:ok, view, _html} = live(conn, path)

      render_change(view, "toggle_all_selections", %{all_selections: true})
      result = render_click(view, "bulk-rerun", %{type: "all"})
      {:ok, view, html} = follow_redirect(result, conn)
      render_async(view)

      assert html =~ "New runs enqueued for 5 workorders"

      view
      |> form("#selection-form-#{hd(other_4_work_orders).id}")
      |> render_change(%{selected: true})

      result = render_click(view, "bulk-rerun", %{type: "selected"})
      {:ok, _view, html} = follow_redirect(result, conn)
      assert html =~ "New run enqueued for 1 workorder"
    end

    @tag role: :editor
    test "selecting all work orders in the page prompts the user to rerun all runs",
         %{conn: conn, project: project} do
      trigger = build(:trigger, type: :webhook)

      job_b =
        build(:job,
          body: ~s[fn(state => { return {...state, extra: "data"} })],
          name: "First Job"
        )

      workflow =
        build(:workflow, project: project)
        |> with_job(job_b)
        |> with_trigger(trigger)
        |> with_edge({trigger, job_b})
        |> insert()

      job_b = workflow.jobs |> List.first()
      trigger = workflow.triggers |> List.first()

      dataclip = insert(:dataclip, project: project)

      work_order_b =
        insert(:workorder,
          workflow: workflow,
          trigger: trigger,
          dataclip: dataclip,
          last_activity: DateTime.utc_now()
        )

      insert(:run,
        work_order: work_order_b,
        dataclip: dataclip,
        starting_trigger: trigger,
        steps: [
          %{
            job: job_b,
            started_at: build(:timestamp),
            finished_at: build(:timestamp),
            exit_reason: "success",
            input_dataclip: dataclip
          }
        ]
      )

      {:ok, view, _html} =
        live_async(
          conn,
          Routes.project_run_index_path(conn, :index, project.id,
            filters: %{
              body: true,
              log: true,
              success: true,
              pending: true,
              crashed: true,
              killed: true,
              running: true,
              failed: true
            }
          )
        )

      # All work orders have been selected, but there's only one page
      html =
        render_change(view, "toggle_all_selections", %{all_selections: true})

      refute html =~ "Rerun all 2 matching work orders from start"
      assert html =~ "Rerun 2 selected work orders from start"

      # uncheck 1 work order
      view
      |> form("#selection-form-#{work_order_b.id}")
      |> render_change(%{selected: false})

      updated_html = render(view)
      refute updated_html =~ "Rerun all 2 matching work orders from start"
      assert updated_html =~ "Rerun 1 selected work order from start"
    end

    test "workorders with wiped dataclips cannot be selected",
         %{conn: conn, project: project, work_order: work_order_1} do
      %{triggers: [trigger], jobs: [job | _rest]} =
        workflow = insert(:simple_workflow, project: project)

      dataclip = insert(:dataclip, body: nil, wiped_at: DateTime.utc_now())

      work_order_2 =
        insert(:workorder,
          workflow: workflow,
          trigger: trigger,
          dataclip: dataclip,
          state: :success
        )
        |> with_run(
          state: :success,
          dataclip: dataclip,
          starting_trigger: trigger,
          finished_at: build(:timestamp),
          steps: [
            build(:step,
              finished_at: DateTime.utc_now(),
              job: job,
              exit_reason: "success",
              input_dataclip: nil,
              output_dataclip: nil
            )
          ]
        )

      {:ok, view, _html} =
        live_async(conn, Routes.project_run_index_path(conn, :index, project.id))

      # Try selecting
      assert_raise ArgumentError, fn ->
        view
        |> form("#selection-form-#{work_order_2.id}")
        |> render_change(%{selected: true})
      end

      # Workorder with existing dataclip can be selected
      assert view
             |> form("#selection-form-#{work_order_1.id}")
             |> render_change(%{selected: true}) =~
               "Rerun 1 selected work order from start"

      # Select All work orders. We have 2 workorders
      html =
        render_change(view, "toggle_all_selections", %{all_selections: true})

      refute html =~ "Rerun 2 selected work orders from start"

      assert html =~ "Rerun 1 selected work order from start",
             "Only one workorder gets selected"
    end
  end

  describe "bulk_rerun_modal" do
    test "2 run buttons are present when all entries have been selected" do
      html =
        render_component(
          &LightningWeb.RunLive.Components.bulk_rerun_modal/1,
          id: "bulk-rerun-modal",
          page_number: 1,
          pages: 3,
          total_entries: 25,
          all_selected?: true,
          selected_count: 10,
          filters: %SearchParams{},
          workflows: [{"Workflow a", "someid"}]
        )

      assert html =~ "Rerun all 25 matching work orders from start"
      assert html =~ "Rerun 10 selected work orders from start"
    end

    test "only 1 run button present when some entries have been selected" do
      html =
        render_component(
          &LightningWeb.RunLive.Components.bulk_rerun_modal/1,
          id: "bulk-rerun-modal",
          page_number: 1,
          total_entries: 25,
          all_selected?: false,
          selected_count: 5,
          filters: %SearchParams{},
          workflows: [{"Workflow a", "someid"}]
        )

      refute html =~ "Rerun all 25 matching work orders from start"
      assert html =~ "Rerun 5 selected work orders from start"
    end

    test "the filter queries are displayed correctly when all entries have been selected" do
      assigns = %{
        id: "bulk-rerun-modal",
        page_number: 1,
        pages: 3,
        total_entries: 25,
        all_selected?: true,
        selected_count: 5,
        filters: %SearchParams{},
        workflows: [{"Workflow A", "someid"}]
      }

      # status
      html =
        render_component(
          &LightningWeb.RunLive.Components.bulk_rerun_modal/1,
          %{assigns | filters: %SearchParams{status: ["success"]}}
        )

      assert html =~ safe_html_string("having a status of 'Success'")

      html =
        render_component(
          &LightningWeb.RunLive.Components.bulk_rerun_modal/1,
          %{assigns | filters: %SearchParams{status: ["success", "failed"]}}
        )

      assert html =~
               safe_html_string(
                 "having a status of either 'Success' or 'Failed'"
               )

      # search fields
      html =
        render_component(
          &LightningWeb.RunLive.Components.bulk_rerun_modal/1,
          %{
            assigns
            | filters: %SearchParams{
                search_fields: ["body"],
                search_term: "TestSearch"
              }
          }
        )

      assert html =~ "whose run Input contain TestSearch"

      html =
        render_component(
          &LightningWeb.RunLive.Components.bulk_rerun_modal/1,
          %{
            assigns
            | filters: %SearchParams{
                search_fields: ["body", "log"],
                search_term: "TestSearch"
              }
          }
        )

      assert html =~ "whose run Input and Logs contain TestSearch"

      # workflow
      html =
        render_component(
          &LightningWeb.RunLive.Components.bulk_rerun_modal/1,
          %{assigns | filters: %SearchParams{workflow_id: nil}}
        )

      refute html =~ "for Workflow A workflow"

      html =
        render_component(
          &LightningWeb.RunLive.Components.bulk_rerun_modal/1,
          %{assigns | filters: %SearchParams{workflow_id: "someid"}}
        )

      assert html =~ "for Workflow A workflow"

      # Run dates
      html =
        render_component(
          &LightningWeb.RunLive.Components.bulk_rerun_modal/1,
          %{
            assigns
            | filters: %SearchParams{date_after: ~U[2023-04-01 08:05:00.00Z]}
          }
        )

      assert html =~ "which was last run after 1/4/23 at 8:05am"

      html =
        render_component(
          &LightningWeb.RunLive.Components.bulk_rerun_modal/1,
          %{
            assigns
            | filters: %SearchParams{date_before: ~U[2023-04-01 08:05:00.00Z]}
          }
        )

      assert html =~ "which was last run before 1/4/23 at 8:05am"

      html =
        render_component(
          &LightningWeb.RunLive.Components.bulk_rerun_modal/1,
          %{
            assigns
            | filters: %SearchParams{
                date_after: ~U[2023-01-01 16:20:00.00Z],
                date_before: ~U[2023-04-01 08:05:00.00Z]
              }
          }
        )

      assert html =~
               "which was last run between 1/4/23 at 8:05am and 1/1/23 at 4:20pm"

      # Work Order dates
      html =
        render_component(
          &LightningWeb.RunLive.Components.bulk_rerun_modal/1,
          %{
            assigns
            | filters: %SearchParams{wo_date_after: ~U[2023-04-01 08:05:00.00Z]}
          }
        )

      assert html =~ "received after 1/4/23 at 8:05am"

      html =
        render_component(
          &LightningWeb.RunLive.Components.bulk_rerun_modal/1,
          %{
            assigns
            | filters: %SearchParams{wo_date_before: ~U[2023-04-01 08:05:00.00Z]}
          }
        )

      assert html =~ "received before 1/4/23 at 8:05am"

      html =
        render_component(
          &LightningWeb.RunLive.Components.bulk_rerun_modal/1,
          %{
            assigns
            | filters: %SearchParams{
                wo_date_after: ~U[2023-01-01 16:20:00.00Z],
                wo_date_before: ~U[2023-04-01 08:05:00.00Z]
              }
          }
        )

      assert html =~
               "received between 1/4/23 at 8:05am and 1/1/23 at 4:20pm"
    end
  end

  defp safe_html_string(string) do
    string |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()
  end

  defp select_workflow_in_dropdown(view, workflow_id) do
    view
    |> element("#select-workflow-#{workflow_id}")
    |> render_click()

    view |> render_async()
  end

  defp has_workflow_in_dropdown?(view, workflow_id) do
    view |> element("#select-workflow-#{workflow_id}") |> has_element?()
  end
end
