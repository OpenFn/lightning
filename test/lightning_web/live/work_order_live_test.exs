defmodule LightningWeb.RunWorkOrderTest do
  alias Lightning.Repo
  use LightningWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Lightning.Attempt
  alias Lightning.WorkOrders.SearchParams

  import Lightning.Factories

  setup :register_and_log_in_user
  setup :create_project_for_current_user

  describe "Index" do
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
        live(conn, Routes.project_run_index_path(conn, :index, project.id))

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

    test "WorkOrderComponent", %{
      project: project
    } do
      %{jobs: [job]} = workflow = insert(:simple_workflow, project: project)

      dataclip = insert(:dataclip)

      work_order =
        insert(:workorder, workflow: workflow, dataclip: dataclip)
        |> with_attempt(
          starting_job: job,
          dataclip: dataclip,
          runs: [
            %{
              job: job,
              started_at: build(:timestamp),
              finished_at: nil,
              exit_code: nil,
              input_dataclip: dataclip
            }
          ]
        )

      assert render_component(LightningWeb.RunLive.WorkOrderComponent,
               id: work_order.id,
               work_order: work_order
             ) =~ work_order.dataclip_id
    end

    test "lists all workorders", %{
      conn: conn,
      project: project
    } do
      workflow = insert(:workflow, project: project, name: "my workflow")
      trigger = insert(:trigger, type: :webhook, workflow: workflow)
      job = insert(:job, workflow: workflow)

      dataclip = insert(:dataclip)

      work_order =
        insert(:workorder,
          workflow: workflow,
          trigger: trigger,
          dataclip: dataclip
        )

      %{id: attempt_id} =
        insert(:attempt,
          work_order: work_order,
          starting_trigger: trigger,
          dataclip: dataclip,
          finished_at: build(:timestamp),
          runs: [
            build(:run,
              job: job,
              started_at: build(:timestamp),
              finished_at: build(:timestamp),
              exit_code: 1,
              input_dataclip: dataclip
            )
          ]
        )

      {:ok, view, html} =
        live(conn, Routes.project_run_index_path(conn, :index, project.id))

      assert html =~ "History"

      table =
        view
        |> element("section#inner_content div[data-entity='work_order_index']")
        |> render()

      assert table =~ workflow.name
      assert table =~ "#{dataclip.id}"

      # toggle work_order details
      # TODO move to test work_order_component

      assert view
             |> element(
               "section#inner_content div[data-entity='work_order_list'] > div:first-child button[phx-click='toggle_details']"
             )
             |> render_click() =~ "attempt-#{attempt_id}"

      refute view
             |> element(
               "section#inner_content div[data-entity='work_order_list'] > div:first-child button[phx-click='toggle_details']"
             )
             |> render_click() =~ "attempt-#{attempt_id}"
    end
  end

  describe "Search and Filtering" do
    test "Search form is displayed", %{
      conn: conn,
      project: project
    } do
      workflow = insert(:workflow, project: project)
      trigger = insert(:trigger, type: :webhook, workflow: workflow)
      job = insert(:job, workflow: workflow)

      dataclip = insert(:dataclip)

      reason =
        insert(:reason,
          type: :webhook,
          trigger: trigger,
          dataclip: dataclip
        )

      work_order = insert(:workorder, workflow: workflow, reason: reason)

      now = Timex.now()

      %{id: _attempt_id} =
        Attempt.new(%{
          work_order_id: work_order.id,
          reason_id: reason.id,
          runs: [
            %{
              job_id: job.id,
              started_at: now |> Timex.shift(seconds: -25),
              finished_at: now |> Timex.shift(seconds: -1),
              exit_code: 1,
              input_dataclip_id: dataclip.id
            }
          ]
        })
        |> Lightning.Repo.insert!()

      {:ok, view, html} =
        live(conn, Routes.project_run_index_path(conn, :index, project.id))

      assert html =~ "Status"

      assert view
             |> element("input#run-filter-form_success[checked]")
             |> has_element?()

      assert view
             |> element("input#run-filter-form_failure[checked]")
             |> has_element?()

      assert view
             |> element("input#run-filter-form_timeout[checked]")
             |> has_element?()

      assert view
             |> element("input#run-filter-form_crash[checked]")
             |> has_element?()

      assert view
             |> element("input#run-filter-form_pending[checked]")
             |> has_element?()

      assert view
             |> element("input#run-search-form_search_term")
             |> has_element?()

      ## both log and body select
      assert view
             |> element(
               "input#run-both-search-form_body[type='hidden'][value='true']"
             )
             |> has_element?()

      assert view
             |> element(
               "input#run-both-search-form_log[type='hidden'][value='true']"
             )
             |> has_element?()

      ## individual search for body
      assert view
             |> element(
               "input#run-body-search-form_body[type='hidden'][value='true']"
             )
             |> has_element?()

      assert view
             |> element(
               "input#run-body-search-form_log[type='hidden'][value='false']"
             )
             |> has_element?()

      ## individual search for log
      assert view
             |> element(
               "input#run-log-search-form_body[type='hidden'][value='false']"
             )
             |> has_element?()

      assert view
             |> element(
               "input#run-log-search-form_log[type='hidden'][value='true']"
             )
             |> has_element?()
    end

    test "Run with failure status shows when option checked", %{
      conn: conn,
      project: project
    } do
      workflow = insert(:workflow, project: project)
      trigger = insert(:trigger, type: :webhook, workflow: workflow)
      job = insert(:job, workflow: workflow)

      dataclip = insert(:dataclip)

      reason =
        insert(:reason,
          type: :webhook,
          trigger: trigger,
          dataclip: dataclip
        )

      work_order = insert(:workorder, workflow: workflow, reason: reason)

      now = Timex.now()

      %{id: _attempt_id} =
        Attempt.new(%{
          work_order_id: work_order.id,
          reason_id: reason.id,
          runs: [
            %{
              job_id: job.id,
              started_at: now |> Timex.shift(seconds: -25),
              finished_at: now |> Timex.shift(seconds: -1),
              exit_code: 1,
              input_dataclip_id: dataclip.id
            }
          ]
        })
        |> Lightning.Repo.insert!()

      {:ok, view, _html} =
        live(conn, Routes.project_run_index_path(conn, :index, project.id))

      div =
        view
        |> element(
          "section#inner_content div[data-entity='work_order_list'] > div:first-child > div:last-child"
        )
        |> render()

      assert div =~ "Failure"

      # uncheck :failure

      view
      |> form("#run-filter-form", filters: %{"failure" => "false"})
      |> render_submit()

      refute view
             |> element(
               "section#inner_content div[data-entity='work _order_list'] > div:first-child > div:last-child"
             )
             |> has_element?()

      # recheck failure

      view
      |> form("#run-filter-form", filters: %{"failure" => "true"})
      |> render_submit()

      div =
        view
        |> element(
          "section#inner_content div[data-entity='work_order_list'] > div:first-child > div:last-child"
        )
        |> render()

      assert div =~ "Failure"
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

      dataclip = insert(:dataclip)

      insert(:workorder,
        workflow: workflow,
        trigger: trigger,
        dataclip: dataclip,
        attempts: [
          build(:attempt,
            starting_trigger: trigger,
            dataclip: dataclip,
            runs: [
              build(:run,
                job: job,
                input_dataclip: dataclip,
                started_at: build(:timestamp),
                finished_at: build(:timestamp),
                exit_code: 0
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

      dataclip_two = insert(:dataclip)

      insert(:workorder,
        workflow: workflow_two,
        trigger: trigger_two,
        dataclip: dataclip_two,
        attempts: [
          build(:attempt,
            starting_trigger: trigger_two,
            dataclip: dataclip_two,
            runs: [
              build(:run,
                job: job_two,
                input_dataclip: dataclip_two,
                started_at: build(:timestamp),
                finished_at: build(:timestamp),
                exit_code: 1
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

      assert view
             |> element("#select-workflow-#{job.workflow_id}")
             |> has_element?()

      assert view
             |> element("#select-workflow-#{job_two.workflow_id}")
             |> has_element?()

      refute view
             |> element("#select-workflow-#{job_other_project.workflow_id}")
             |> has_element?()

      assert view
             |> element("#select-workflow-#{job_two.workflow_id}")
             |> render_click()

      div =
        view
        |> element(
          "section#inner_content div[data-entity='work_order_list'] > div:first-child"
        )
        |> render()

      refute div =~ "workflow 1"
      assert div =~ "workflow 2"

      assert view
             |> element("#select-workflow-#{job.workflow_id}")
             |> render_click()

      div =
        view
        |> element(
          "section#inner_content div[data-entity='work_order_list'] > div:first-child"
        )
        |> render()

      assert div =~ "workflow 1"
      refute div =~ "workflow 2"
    end

    test "Filter by run finished_at", %{
      conn: conn,
      project: project
    } do
      workflow_one = insert(:workflow, project: project)
      trigger_one = insert(:trigger, type: :webhook, workflow: workflow_one)
      job_one = insert(:job, workflow: workflow_one)

      dataclip = insert(:dataclip)

      reason =
        insert(:reason,
          type: :webhook,
          trigger: trigger_one,
          dataclip: dataclip
        )

      work_order = insert(:workorder, workflow: workflow_one, reason: reason)
      expected_d1 = Timex.now() |> Timex.shift(days: -12)

      %{id: _attempt_id} =
        Attempt.new(%{
          work_order_id: work_order.id,
          reason_id: reason.id,
          runs: [
            %{
              job_id: job_one.id,
              started_at: expected_d1,
              finished_at: expected_d1,
              exit_code: 0,
              input_dataclip_id: dataclip.id
            }
          ]
        })
        |> Lightning.Repo.insert!()

      workflow_two = insert(:workflow, project: project)
      trigger_two = insert(:trigger, type: :webhook, workflow: workflow_two)
      job_two = insert(:job, workflow: workflow_two)

      dataclip = insert(:dataclip)

      reason =
        insert(:reason,
          type: :webhook,
          trigger: trigger_two,
          dataclip: dataclip
        )

      work_order = insert(:workorder, workflow: workflow_two, reason: reason)

      expected_d2 = Timex.now() |> Timex.shift(days: -10)

      %{id: _attempt_id} =
        Attempt.new(%{
          work_order_id: work_order.id,
          reason_id: reason.id,
          runs: [
            %{
              job_id: job_two.id,
              started_at: expected_d2,
              finished_at: expected_d2,
              exit_code: 1,
              input_dataclip_id: dataclip.id
            }
          ]
        })
        |> Lightning.Repo.insert!()

      {:ok, view, html} =
        live(
          conn,
          Routes.project_run_index_path(conn, :index, project.id)
        )

      assert html =~ expected_d2 |> Timex.format!("%d/%b/%y", :strftime)
      assert html =~ expected_d1 |> Timex.format!("%d/%b/%y", :strftime)

      # set date after to 11 days ago, only see second workorder

      result =
        view
        |> element("form#run-filter-form")
        |> render_submit(%{
          "filters[date_after]" => Timex.now() |> Timex.shift(days: -11)
        })

      refute result =~ expected_d1 |> Timex.format!("%d/%b/%y", :strftime)
      assert result =~ expected_d2 |> Timex.format!("%d/%b/%y", :strftime)

      # set date before to 12 days ago, only see first workorder

      # reset after date
      view
      |> element("form#run-filter-form")
      |> render_submit(%{"filters[date_after]" => nil})

      result =
        view
        |> element("form#run-filter-form")
        |> render_submit(%{
          "filters[date_before]" => Timex.now() |> Timex.shift(days: -12)
        })

      assert result =~ expected_d1 |> Timex.format!("%d/%b/%y", :strftime)
      refute result =~ expected_d2 |> Timex.format!("%d/%b/%y", :strftime)

      # reset before date
      result =
        view
        |> element("form#run-filter-form")
        |> render_submit(%{"filters[date_before]" => nil})

      assert result =~ expected_d1 |> Timex.format!("%d/%b/%y", :strftime)
      assert result =~ expected_d2 |> Timex.format!("%d/%b/%y", :strftime)
    end

    test "Filter by run run_log and dataclip_body", %{
      conn: conn,
      project: project
    } do
      # workflow 1 -> 1 run success -> contains body with some data
      # workflow 2 -> 1 run failure -> contains log with some log

      workflow_one = insert(:workflow, project: project, name: "workflow 1")
      trigger_one = insert(:trigger, type: :webhook, workflow: workflow_one)

      job_one =
        insert(:job,
          workflow: workflow_one,
          body: ~s[fn(state => { return {...state, extra: "data"} })]
        )

      dataclip =
        insert(:dataclip,
          type: :http_request,
          body: %{"username" => "eliaswalyba"}
        )

      reason =
        insert(:reason,
          type: :webhook,
          trigger: trigger_one,
          dataclip: dataclip
        )

      work_order = insert(:workorder, workflow: workflow_one, reason: reason)
      expected_d1 = Timex.now() |> Timex.shift(days: -12)

      %{id: _attempt_id} =
        Attempt.new(%{
          work_order_id: work_order.id,
          reason_id: reason.id,
          runs: [
            %{
              job_id: job_one.id,
              started_at: expected_d1,
              finished_at: expected_d1 |> Timex.shift(minutes: 2),
              exit_code: 0,
              input_dataclip_id: dataclip.id
            }
          ]
        })
        |> Lightning.Repo.insert!()

      workflow_two = insert(:workflow, project: project, name: "workflow 2")
      trigger_two = insert(:trigger, type: :webhook, workflow: workflow_two)
      job_two = insert(:job, workflow: workflow_two)

      dataclip =
        insert(:dataclip, type: :http_request, body: %{"username" => "qassim"})

      reason =
        insert(:reason,
          type: :webhook,
          trigger: trigger_two,
          dataclip: dataclip
        )

      work_order = insert(:workorder, workflow: workflow_two, reason: reason)

      expected_d2 = Timex.now() |> Timex.shift(days: -10)

      %{id: _attempt_id} =
        Attempt.new(%{
          work_order_id: work_order.id,
          reason_id: reason.id,
          runs: [
            %{
              job_id: job_two.id,
              started_at: expected_d2,
              finished_at: expected_d2 |> Timex.shift(minutes: 5),
              exit_code: 1,
              input_dataclip_id: dataclip.id,
              log_lines: [
                %{body: "Hi mom!"},
                %{body: "Log me something fun."},
                %{body: "It's another great log."}
              ]
            }
          ]
        })
        |> Lightning.Repo.insert!()

      {:ok, view, _html} =
        live(conn, Routes.project_run_index_path(conn, :index, project.id))

      div =
        view
        |> element(
          "section#inner_content div[data-entity='work_order_list'] > div:first-child > div:last-child"
        )
        |> render()

      assert div =~ "Failure"

      # search :some data

      view
      |> search_for("xxxx", [])

      refute workflow_displayed(view, "workflow 1")
      refute workflow_displayed(view, "workflow 2")

      view
      |> search_for("xxxx", [:body, :log])

      refute workflow_displayed(view, "workflow 1")
      refute workflow_displayed(view, "workflow 2")

      view
      |> search_for("eliaswalyba", [:body, :log])

      assert workflow_displayed(view, "workflow 1")
      refute workflow_displayed(view, "workflow 2")

      view
      |> search_for("qassim", [:body, :log])

      refute workflow_displayed(view, "workflow 1")
      assert workflow_displayed(view, "workflow 2")

      view
      |> search_for("some log", [:body])

      refute workflow_displayed(view, "workflow 1")
      refute workflow_displayed(view, "workflow 2")

      view
      |> search_for("some log", [:log])

      refute workflow_displayed(view, "workflow 1")
      refute workflow_displayed(view, "workflow 2")
    end
  end

  describe "Show" do
    test "no access to project on show", %{
      conn: conn,
      project: project_scoped
    } do
      workflow_scoped = insert(:workflow, project: project_scoped)
      job = insert(:job, workflow: workflow_scoped)
      run = insert(:run, job: job)

      {:ok, _view, html} =
        live(
          conn,
          Routes.project_run_show_path(conn, :show, project_scoped.id, run.id)
        )

      assert html =~ run.id

      project_unscoped = insert(:project)

      job = insert(:job, workflow: workflow_scoped)
      run = insert(:run, job: job)

      error =
        live(
          conn,
          Routes.project_run_show_path(
            conn,
            :show,
            project_unscoped.id,
            run.id
          )
        )

      assert error ==
               {:error, {:redirect, %{flash: %{"nav" => :not_found}, to: "/"}}}
    end

    test "log_view component" do
      log_lines = ["First line", "Second line"]

      html =
        render_component(&LightningWeb.RunLive.Components.log_view/1,
          log: log_lines
        )
        |> Floki.parse_fragment!()

      assert html |> Floki.find("div[data-line-number]") |> length() == 2

      # Check that the log lines are present.
      # Replace the resulting utf-8 &nbsp; back into a regular space.
      assert html
             |> Floki.find("div[data-log-line]")
             |> Floki.text(sep: "\n")
             |> String.replace(<<160::utf8>>, " ") ==
               log_lines |> Enum.join("\n")
    end

    test "run_details component with finished run" do
      now = Timex.now()

      started_at = now |> Timex.shift(seconds: -25)
      finished_at = now |> Timex.shift(seconds: -1)

      run = insert(:run, started_at: started_at, finished_at: finished_at)

      html =
        render_component(&LightningWeb.RunLive.Components.run_details/1,
          run: run
        )
        |> Floki.parse_fragment!()

      assert html
             |> Floki.find("div#finished-at-#{run.id} > div:nth-child(2)")
             |> Floki.text() =~
               Calendar.strftime(finished_at, "%c")

      assert html
             |> Floki.find("div#ran-for-#{run.id} > div:nth-child(2)")
             |> Floki.text() =~
               "24000 ms"

      assert html
             |> Floki.find("div#exit-code-#{run.id} > div:nth-child(2)")
             |> Floki.text() =~
               "?"
    end

    test "run_details component with pending run" do
      now = Timex.now()

      started_at = now |> Timex.shift(seconds: -25)
      run = insert(:run, started_at: started_at)

      html =
        render_component(&LightningWeb.RunLive.Components.run_details/1,
          run: run
        )
        |> Floki.parse_fragment!()

      assert html
             |> Floki.find("div#finished-at-#{run.id} > div:nth-child(2)")
             |> Floki.text() =~ "Running..."

      assert html
             |> Floki.find("div#ran-for-#{run.id} > div:nth-child(2)")
             |> Floki.text() =~ "..."

      # TODO: add a timer that counts up from run.started_at
      #  ~r/25\d\d\d ms/

      assert html
             |> Floki.find("div#exit-code-#{run.id} > div:nth-child(2)")
             |> Floki.text() =~
               "?"
    end

    test "by default only the latest attempt is present when there are multiple attempts",
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
          enabled: true,
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
        condition: :always
      )

      dataclip = insert(:dataclip, project: project)

      reason =
        insert(:reason,
          type: :webhook,
          dataclip: dataclip,
          trigger: trigger
        )

      workorder = insert(:workorder, workflow: workflow, reason: reason)

      now = Timex.now()

      attempt_1 =
        insert(:attempt,
          work_order: workorder,
          reason: reason,
          inserted_at: now |> Timex.shift(minutes: -5),
          runs:
            build_list(1, :run, %{
              job: job,
              started_at: now |> Timex.shift(seconds: -40),
              finished_at: now |> Timex.shift(seconds: -20),
              exit_code: nil,
              input_dataclip: dataclip
            })
        )

      attempt_2 =
        insert(:attempt,
          work_order: workorder,
          reason: reason,
          runs:
            build_list(1, :run,
              job: job,
              started_at: Timex.shift(now, seconds: -20),
              finished_at: now,
              exit_code: nil,
              input_dataclip: dataclip
            )
        )

      {:ok, view, _html} =
        live(
          conn,
          Routes.project_run_index_path(conn, :index, project.id)
        )

      view |> element("#toggle_details_for_#{workorder.id}") |> render_click()

      assert has_element?(view, "#attempt_#{attempt_1.id}.hidden")
      refute has_element?(view, "#attempt_#{attempt_2.id}.hidden")
      assert has_element?(view, "#attempt_#{attempt_2.id}")
    end

    test "user can toggle to see all attempts",
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
          enabled: true,
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
        condition: :always
      )

      dataclip = insert(:dataclip, project: project)

      workorder = insert(:workorder, state: :success, workflow: workflow)

      now = Timex.now()

      attempt_1 =
        insert(:attempt,
          work_order: workorder,
          state: :failed,
          starting_trigger: trigger,
          inserted_at: now |> Timex.shift(minutes: -5),
          dataclip: dataclip,
          runs:
            build_list(1, :run, %{
              job: job,
              exit_code: 1,
              started_at: now |> Timex.shift(seconds: -40),
              finished_at: now |> Timex.shift(seconds: -20),
              input_dataclip: dataclip
            })
        )

      attempt_2 =
        insert(:attempt,
          state: :success,
          work_order: workorder,
          starting_job: job,
          dataclip: dataclip,
          runs:
            build_list(1, :run,
              job: job,
              started_at: Timex.shift(now, seconds: -20),
              finished_at: now,
              input_dataclip: dataclip
            )
        )

      {:ok, view, _html} =
        live(
          conn,
          Routes.project_run_index_path(conn, :index, project.id)
        )

      view |> element("#toggle_details_for_#{workorder.id}") |> render_click()

      assert has_element?(view, "#attempt_#{attempt_1.id}.hidden")
      refute has_element?(view, "#attempt_#{attempt_2.id}.hidden")
      assert has_element?(view, "#attempt_#{attempt_2.id}")

      # show all
      view |> element("#toggle_attempts_for_#{workorder.id}") |> render_click()
      refute has_element?(view, "#attempt_#{attempt_1.id}.hidden")
      refute has_element?(view, "#attempt_#{attempt_2.id}.hidden")
      assert has_element?(view, "#attempt_#{attempt_1.id}")
      assert has_element?(view, "#attempt_#{attempt_2.id}")

      # hide some
      view |> element("#toggle_attempts_for_#{workorder.id}") |> render_click()
      assert has_element?(view, "#attempt_#{attempt_1.id}.hidden")
      refute has_element?(view, "#attempt_#{attempt_2.id}.hidden")
      assert has_element?(view, "#attempt_#{attempt_2.id}")
    end
  end

  def search_for(view, term, types) when types == [] do
    search_for(view, term, [:body, :log])
  end

  def search_for(view, term, types) do
    filter_attrs = %{"search_term" => term}

    for type <- [:body, :log] do
      checked = type in types
      Map.put(filter_attrs, "#{type}", "#{checked}")
    end

    view
    |> form("#run-search-form",
      filters: filter_attrs
    )
    |> render_submit()
  end

  def workflow_displayed(view, name) do
    elem =
      view
      |> element(
        "section#inner_content div[data-entity='work_order_list'] > div:first-child"
      )

    if elem |> has_element?() do
      elem |> render() =~ name
    else
      false
    end
  end

  @tag role: :editor
  describe "rerun" do
    setup %{project: project} do
      workflow = insert(:workflow, project: project)
      trigger = insert(:trigger, type: :webhook, workflow: workflow)
      job_a = insert(:job, workflow: workflow)

      dataclip = insert(:dataclip)

      work_order =
        insert(:workorder,
          workflow: workflow,
          trigger: trigger,
          dataclip: dataclip
        )

      attempt =
        insert(:attempt,
          work_order: work_order,
          state: :failed,
          dataclip: dataclip,
          starting_trigger: trigger,
          finished_at: build(:timestamp),
          runs: [
            build(:run,
              job: job_a,
              input_dataclip: dataclip,
              started_at: build(:timestamp),
              finished_at: build(:timestamp),
              exit_code: 1
            )
          ]
        )

      %{attempt: attempt, work_order: work_order}
    end

    @tag role: :editor
    test "Project editors can rerun runs",
         %{conn: conn, project: project, attempt: attempt} do
      [run | _rest] = attempt.runs

      {:ok, view, _html} =
        live(conn, Routes.project_run_index_path(conn, :index, project.id))

      assert view
             |> render_click("rerun", %{
               "attempt_id" => attempt.id,
               "run_id" => run.id
             })
    end

    @tag role: :viewer
    test "Project viewers can't rerun runs",
         %{conn: conn, project: project, attempt: attempt} do
      [run | _rest] = attempt.runs

      {:ok, view, _html} =
        live(conn, Routes.project_run_index_path(conn, :index, project.id))

      assert view
             |> render_click("rerun", %{
               "attempt_id" => attempt.id,
               "run_id" => run.id
             }) =~
               "You are not authorized to perform this action."
    end

    @tag role: :viewer
    test "Project viewers can't rerun runs in bulk from start",
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

      insert(:attempt,
        work_order: work_order_b,
        starting_trigger: trigger,
        dataclip: dataclip,
        finished_at: build(:timestamp),
        runs: [
          %{
            job: job_b,
            started_at: build(:timestamp),
            finished_at: build(:timestamp),
            exit_code: 0,
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
    test "Project editors can rerun runs in bulk from start",
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
          dataclip: dataclip
        )

      insert(:attempt,
        work_order: work_order_b,
        starting_trigger: trigger,
        dataclip: dataclip,
        finished_at: build(:timestamp),
        state: :success,
        runs: [
          %{
            job: job_b,
            started_at: build(:timestamp),
            finished_at: build(:timestamp),
            exit_code: 0,
            input_dataclip: dataclip
          }
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

      assert html =~ "New attempts enqueued for 2 workorders"

      view
      |> form("##{work_order_b.id}-selection-form")
      |> render_change(%{selected: true})

      result = render_click(view, "bulk-rerun", %{type: "selected"})
      {:ok, _view, html} = follow_redirect(result, conn)
      assert html =~ "New attempt enqueued for 1 workorder"
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
          dataclip: dataclip
        )

      insert(:attempt,
        work_order: work_order_b,
        dataclip: dataclip,
        starting_trigger: trigger,
        runs: [
          %{
            job: job_b,
            started_at: build(:timestamp),
            finished_at: build(:timestamp),
            exit_code: 0,
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

      # All work orders have been selected, but there's only one page
      html =
        render_change(view, "toggle_all_selections", %{all_selections: true})

      refute html =~ "Rerun all 2 matching workorders from start"
      assert html =~ "Rerun 2 selected workorders from start"

      view
      |> form("##{work_order_b.id}-selection-form")
      |> render_change(%{selected: false})

      # uncheck 1 work order
      updated_html = render(view)
      refute updated_html =~ "Rerun all 2 matching workorders from start"
      assert updated_html =~ "Rerun 1 selected workorder from start"
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
          selected_count: 5,
          filters: %SearchParams{},
          workflows: [{"Workflow a", "someid"}]
        )

      assert html =~ "Rerun all 25 matching workorders from start"
      assert html =~ "Rerun 5 selected workorders from start"
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

      refute html =~ "Rerun all 25 matching workorders from start"
      assert html =~ "Rerun 5 selected workorders from start"
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

  describe "bulk rerun from job" do
    setup %{project: project} do
      %{project: project, triggers: [trigger], jobs: jobs} =
        workflow = insert(:complex_workflow, project: project)

      dataclip = insert(:dataclip, project: project)

      work_order_1 =
        insert(:workorder,
          workflow: workflow,
          trigger: trigger,
          dataclip: dataclip
        )
        |> with_attempt(
          state: :failed,
          dataclip: dataclip,
          starting_trigger: trigger,
          finished_at: build(:timestamp),
          runs:
            jobs
            |> Enum.map(fn j ->
              build(:run,
                job: j,
                input_dataclip: dataclip,
                started_at: build(:timestamp),
                finished_at: build(:timestamp),
                exit_code: 1
              )
            end)
        )

      dataclip = insert(:dataclip, project: project)

      work_order_2 =
        insert(:workorder,
          workflow: workflow,
          trigger: trigger,
          dataclip: dataclip
        )
        |> with_attempt(
          state: :failed,
          dataclip: dataclip,
          starting_trigger: trigger,
          finished_at: build(:timestamp),
          runs:
            jobs
            |> Enum.map(fn j ->
              build(:run,
                job: j,
                input_dataclip: dataclip,
                started_at: build(:timestamp),
                finished_at: build(:timestamp),
                exit_code: 1
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
          state: :success
        )
        |> with_attempt(
          starting_trigger: trigger,
          dataclip: dataclip,
          finished_at: build(:timestamp),
          runs: [
            %{
              job: job_a,
              started_at: build(:timestamp),
              finished_at: build(:timestamp),
              exit_reason: "success",
              input_dataclip: dataclip,
              exit_code: 0
            }
          ]
        )

      {:ok, view, html} =
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

      refute html =~ "Rerun from..."

      # All work orders have been selected
      refute render_change(view, "toggle_all_selections", %{
               all_selections: true
             }) =~ "Rerun from..."

      # uncheck 1 work order
      view
      |> form("##{work_order_3.id}-selection-form")
      |> render_change(%{selected: false})

      updated_html = render(view)
      assert updated_html =~ "Rerun from..."
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

      refute html =~
               "Find all runs that include this step, and rerun from there"

      assert render_change(view, "toggle_all_selections", %{
               all_selections: true
             }) =~ "Find all runs that include this step, and rerun from there"

      view
      |> form("#select-job-for-rerun-form")
      |> render_change(%{job: job_a.id})

      result = view |> render_click("bulk-rerun", %{type: "all", job: job_a.id})

      {:ok, view, html} = follow_redirect(result, conn)

      assert html =~
               "New attempts enqueued for 2 workorders"

      view
      |> form("##{work_order_1.id}-selection-form")
      |> render_change(%{selected: true})

      view
      |> form("#select-job-for-rerun-form")
      |> render_change(%{job: job_a.id})

      result =
        view |> element("#rerun-selected-from-job-trigger") |> render_click()

      {:ok, _view, html} = follow_redirect(result, conn)

      assert html =~ "New attempt enqueued for 1 workorder"
    end

    test "jobs on the modal are updated every time the selected workflow is changed",
         %{
           conn: conn,
           project: project
         } do
      scenarios =
        Enum.map(1..3, fn _n ->
          workflow = insert(:workflow, project: project)

          work_order =
            insert(:workorder,
              state: :success,
              workflow: workflow,
              trigger: build(:trigger),
              dataclip: build(:dataclip)
            )

          jobs = insert_list(5, :job, workflow: workflow)

          runs =
            Enum.map(
              jobs,
              fn j ->
                build(:run,
                  input_dataclip: build(:dataclip),
                  job: j,
                  started_at: build(:timestamp),
                  finished_at: build(:timestamp),
                  exit_code: 0
                )
              end
            )

          insert(:attempt,
            work_order: work_order,
            finished_at: build(:timestamp),
            starting_trigger: build(:trigger),
            dataclip: build(:dataclip),
            runs: runs
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
            crash: true,
            failure: true
          }
        )

      {:ok, view, _html} = live(conn, path)

      for scenario <- scenarios do
        for job <- scenario.jobs do
          refute has_element?(view, "input#job_#{job.id}")
        end

        # SELECT
        view
        |> form("##{scenario.work_order.id}-selection-form")
        |> render_change(%{selected: true})

        for job <- scenario.jobs do
          assert has_element?(view, "input#job_#{job.id}")
        end

        # UNSELECT
        view
        |> form("##{scenario.work_order.id}-selection-form")
        |> render_change(%{selected: false})
      end
    end

    test "all jobs in the selected workflow are displayed", %{
      workflow: workflow,
      jobs: jobs
    } do
      html =
        render_component(
          LightningWeb.RunLive.RerunJobComponent,
          id: "bulk-rerun-from-start-modal",
          total_entries: 25,
          all_selected?: true,
          selected_count: 5,
          pages: 2,
          filters: %SearchParams{},
          workflow_id: workflow.id
        )

      for job <- jobs do
        assert html =~ job.name
      end
    end

    test "2 run buttons are present when all entries have been selected", %{
      workflow: workflow
    } do
      html =
        render_component(
          LightningWeb.RunLive.RerunJobComponent,
          id: "bulk-rerun-from-start-modal",
          total_entries: 25,
          all_selected?: true,
          selected_count: 5,
          pages: 2,
          filters: %SearchParams{},
          workflow_id: workflow.id
        )

      assert html =~ "Rerun all 25 matching workorders from selected job"
      assert html =~ "Rerun 5 selected workorders from selected job"
    end

    test "only 1 run button is present when some entries have been selected", %{
      workflow: workflow
    } do
      html =
        render_component(
          LightningWeb.RunLive.RerunJobComponent,
          id: "bulk-rerun-from-start-modal",
          total_entries: 25,
          all_selected?: false,
          selected_count: 5,
          pages: 2,
          filters: %SearchParams{},
          workflow_id: workflow.id
        )

      refute html =~ "Rerun all 25 matching workorders from selected job"
      assert html =~ "Rerun 5 selected workorders from selected job"
    end

    test "only 1 run button is present when total pages is 1", %{
      workflow: workflow
    } do
      html =
        render_component(
          LightningWeb.RunLive.RerunJobComponent,
          id: "bulk-rerun-from-start-modal",
          total_entries: 25,
          all_selected?: true,
          selected_count: 5,
          pages: 1,
          filters: %SearchParams{},
          workflow_id: workflow.id
        )

      refute html =~ "Rerun all 25 matching workorders from selected job"
      assert html =~ "Rerun 5 selected workorders from selected job"
    end
  end

  describe "timestamp" do
    test "default option" do
      now = NaiveDateTime.utc_now()

      assert render_component(&LightningWeb.RunLive.Components.timestamp/1,
               timestamp: now
             ) =~
               Timex.format!(
                 now,
                 "%d/%b/%y, %H:%M:%S",
                 :strftime
               )
    end

    test "wrapped option" do
      now = NaiveDateTime.utc_now()

      html =
        render_component(&LightningWeb.RunLive.Components.timestamp/1,
          timestamp: now,
          style: :wrapped
        )

      refute html =~ Timex.format!(now, "%d/%b/%y, %H:%M:%S", :strftime)

      assert html =~ Timex.format!(now, "%d/%b/%y", :strftime)

      assert html =~ Timex.format!(now, "%H:%M:%S", :strftime)
    end

    test "with time only option" do
      now = NaiveDateTime.utc_now()

      html =
        render_component(&LightningWeb.RunLive.Components.timestamp/1,
          timestamp: now,
          style: :time_only
        )

      refute html =~ Timex.format!(now, "%d/%b/%y, %H:%M:%S", :strftime)

      refute html =~ Timex.format!(now, "%d/%b/%y", :strftime)

      assert html =~ Timex.format!(now, "%H:%M:%S", :strftime)
    end
  end
end
