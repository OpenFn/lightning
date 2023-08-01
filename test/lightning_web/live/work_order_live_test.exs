defmodule LightningWeb.RunWorkOrderTest do
  use LightningWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Lightning.Attempt
  alias Lightning.Workorders.SearchParams

  import Lightning.JobsFixtures
  import Lightning.InvocationFixtures
  import Lightning.WorkflowsFixtures

  import Lightning.Factories

  setup :register_and_log_in_user
  setup :create_project_for_current_user

  describe "Index" do
    test "WorkOrderComponent", %{
      project: project
    } do
      %{job: job, trigger: trigger} =
        workflow_job_fixture(
          workflow_name: "my workflow",
          project_id: project.id,
          body: ~s[fn(state => { return {...state, extra: "data"} })]
        )

      dataclip = dataclip_fixture()

      reason =
        reason_fixture(
          trigger_id: trigger.id,
          dataclip_id: dataclip.id
        )

      work_order =
        work_order_fixture(workflow_id: job.workflow_id, reason_id: reason.id)

      now = Timex.now()

      Attempt.new(%{
        work_order_id: work_order.id,
        reason_id: reason.id,
        runs: [
          %{
            job_id: job.id,
            started_at: now |> Timex.shift(seconds: -25),
            finished_at: nil,
            exit_code: nil,
            input_dataclip_id: dataclip.id
          }
        ]
      })
      |> Lightning.Repo.insert!()

      render_component(LightningWeb.RunLive.WorkOrderComponent,
        id: work_order.id,
        work_order: work_order
      ) =~ "work_order"
    end

    test "lists all workorders", %{
      conn: conn,
      project: project
    } do
      %{job: job, trigger: trigger} =
        workflow_job_fixture(
          workflow_name: "my workflow",
          project_id: project.id,
          body: ~s[fn(state => { return {...state, extra: "data"} })]
        )

      dataclip = dataclip_fixture()

      reason =
        reason_fixture(
          trigger_id: trigger.id,
          dataclip_id: dataclip.id
        )

      work_order =
        work_order_fixture(workflow_id: job.workflow_id, reason_id: reason.id)

      now = Timex.now()

      %{id: attempt_id} =
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

      # {:error, {:live_redirect, %{flash: %{}, to: destination}}} =
      live(
        conn,
        Routes.project_run_index_path(conn, :index, project.id)
      )

      Routes.project_run_index_path(conn, :index, project.id)

      # assert destination =~
      #          "/projects/#{project.id}/runs?filters[body]=true&filters[crash]=true&filters[date_after]="

      # assert destination =~
      #          "&filters[date_before]=&filters[failure]=true&filters[log]=true&filters[pending]=true&filters[search_term]=&filters[success]=true&filters[timeout]=true&filters[wo_date_after]=&filters[wo_date_before]=&filters[workflow_id]=&project_id=#{project.id}"

      {:ok, view, html} =
        live(conn, Routes.project_run_index_path(conn, :index, project.id))

      assert html =~ "History"

      table =
        view
        |> element("section#inner_content div[data-entity='work_order_index']")
        |> render()

      assert table =~ "my workflow"
      assert table =~ "#{reason.dataclip_id}"

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

    test "When the most recent run is finished without exit code, work_order status is 'Timeout'",
         %{conn: conn, project: project} do
      %{job: job_a, trigger: trigger} =
        workflow_job_fixture(
          project_id: project.id,
          body: ~s[fn(state => { return {...state, extra: "data"} })]
        )

      work_order = work_order_fixture(workflow_id: job_a.workflow_id)

      dataclip = dataclip_fixture()

      reason =
        reason_fixture(
          trigger_id: trigger.id,
          dataclip_id: dataclip.id
        )

      now = Timex.now()

      Attempt.new(%{
        work_order_id: work_order.id,
        reason_id: reason.id,
        runs: [
          %{
            job_id: job_a.id,
            started_at: now |> Timex.shift(seconds: -25),
            finished_at: now |> Timex.shift(seconds: 25),
            exit_code: nil,
            input_dataclip_id: dataclip.id
          }
        ]
      })
      |> Lightning.Repo.insert!()

      {:ok, view, _html} =
        live(
          conn,
          Routes.project_run_index_path(conn, :index, job_a.workflow.project_id)
        )

      div =
        view
        |> element("section#inner_content div[data-entity='work_order_list']")
        |> render()

      assert div =~ "Timeout"
    end

    test "When the most recent run is not complete, work_order status is 'Pending'",
         %{conn: conn, project: project} do
      %{job: job_a, trigger: trigger} =
        workflow_job_fixture(
          project_id: project.id,
          body: ~s[fn(state => { return {...state, extra: "data"} })]
        )

      work_order = work_order_fixture(workflow_id: job_a.workflow_id)

      dataclip = dataclip_fixture()

      reason =
        reason_fixture(
          trigger_id: trigger.id,
          dataclip_id: dataclip.id
        )

      now = Timex.now()

      Attempt.new(%{
        work_order_id: work_order.id,
        reason_id: reason.id,
        runs: [
          %{
            job_id: job_a.id,
            started_at: now |> Timex.shift(seconds: -25),
            finished_at: nil,
            exit_code: nil,
            input_dataclip_id: dataclip.id
          }
        ]
      })
      |> Lightning.Repo.insert!()

      {:ok, view, _html} =
        live(
          conn,
          Routes.project_run_index_path(conn, :index, job_a.workflow.project_id)
        )

      div =
        view
        |> element("section#inner_content div[data-entity='work_order_list']")
        |> render()

      assert div =~ "Pending"
    end

    test "When run A,B and C are successful, work_order status is 'Success'",
         %{conn: conn, project: project} do
      %{job: job_a, trigger: trigger} =
        workflow_job_fixture(
          project_id: project.id,
          body: ~s[fn(state => { return {...state, extra: "data"} })]
        )

      job_b =
        job_fixture(
          trigger: %{type: :on_job_success, upstream_job_id: job_a.id},
          body: ~s[fn(state => state)],
          workflow_id: job_a.workflow_id
        )

      job_c =
        job_fixture(
          trigger: %{type: :on_job_success, upstream_job_id: job_b.id},
          body: ~s[fn(state => state)],
          workflow_id: job_a.workflow_id
        )

      dataclip = dataclip_fixture(project_id: project.id)

      reason =
        reason_fixture(
          trigger_id: trigger.id,
          dataclip_id: dataclip.id
        )

      work_order =
        work_order_fixture(
          project_id: project.id,
          workflow_id: job_a.workflow_id,
          reason_id: reason.id
        )

      now = Timex.now()

      Attempt.new(%{
        work_order_id: work_order.id,
        reason_id: reason.id,
        runs: [
          %{
            job_id: job_a.id,
            started_at: now |> Timex.shift(seconds: -25),
            finished_at: now |> Timex.shift(seconds: -20),
            exit_code: 0,
            input_dataclip_id: dataclip.id
          },
          %{
            job_id: job_b.id,
            started_at: now |> Timex.shift(seconds: -10),
            finished_at: now |> Timex.shift(seconds: -5),
            exit_code: 0,
            input_dataclip_id: dataclip_fixture(project_id: project.id).id
          },
          %{
            job_id: job_c.id,
            started_at: now |> Timex.shift(seconds: -5),
            finished_at: now |> Timex.shift(seconds: -1),
            exit_code: 0,
            input_dataclip_id: dataclip_fixture(project_id: project.id).id
          }
        ]
      })
      |> Lightning.Repo.insert!()

      Lightning.Invocation.search_workorders(project).entries()

      {:ok, view, _html} =
        live(
          conn,
          Routes.project_run_index_path(conn, :index, job_a.workflow.project_id)
        )

      div =
        view
        |> element(
          "section#inner_content div[data-entity='work_order_list'] > div:first-child > div:last-child"
        )
        |> render()

      assert div =~ "Success"
    end

    test "When run A and B are successful but C fails, work_order status is 'Failure'",
         %{conn: conn, project: project} do
      %{job: job_a, trigger: trigger} =
        workflow_job_fixture(
          name: "Job A",
          project_id: project.id,
          body: ~s[fn(state => { return {...state, extra: "data"} })]
        )

      job_b =
        job_fixture(
          name: "Job B",
          trigger: %{type: :on_job_success, upstream_job_id: job_a.id},
          body: ~s[fn(state => state)],
          workflow_id: job_a.workflow_id
        )

      job_c =
        job_fixture(
          name: "Job C",
          trigger: %{type: :on_job_success, upstream_job_id: job_b.id},
          body: ~s[fn(state => { throw new Error("I'm supposed to fail.") })],
          workflow_id: job_a.workflow_id
        )

      work_order = work_order_fixture(workflow_id: job_a.workflow_id)

      dataclip = dataclip_fixture(project_id: project.id)

      now = Timex.now()

      Attempt.new(%{
        work_order_id: work_order.id,
        reason_id:
          reason_fixture(
            trigger_id: trigger.id,
            dataclip_id: dataclip.id
          ).id,
        runs: [
          %{
            job_id: job_a.id,
            started_at: now |> Timex.shift(seconds: -25),
            finished_at: now |> Timex.shift(seconds: -20),
            exit_code: 0,
            input_dataclip_id: dataclip.id
          },
          %{
            job_id: job_b.id,
            started_at: now |> Timex.shift(seconds: -25),
            finished_at: now |> Timex.shift(seconds: -20),
            exit_code: 0,
            input_dataclip_id: dataclip_fixture(project_id: project.id).id
          },
          %{
            job_id: job_c.id,
            started_at: now |> Timex.shift(seconds: -25),
            finished_at: now |> Timex.shift(seconds: -20),
            exit_code: 1,
            input_dataclip_id: dataclip_fixture(project_id: project.id).id
          }
        ]
      })
      |> Lightning.Repo.insert!()

      {:ok, view, _html} =
        live(
          conn,
          Routes.project_run_index_path(conn, :index, job_a.workflow.project_id)
        )

      assert view
             |> has_element?(
               "section#inner_content div[data-entity='work_order_list'] > div:first-child > div:last-child",
               "Failure"
             )

      assert view
             |> element(
               "section#inner_content div[data-entity='work_order_list'] > div:first-child button[phx-click='toggle_details']"
             )
             |> render_click() =~ "Failure"

      {:ok, view, _html} =
        view
        |> element(
          "section#inner_content div[data-entity='work_order_list'] > div:first-child a",
          "Job A"
        )
        |> render_click()
        |> follow_redirect(conn)

      assert view
             |> has_element?(
               "div[id^=finished-at]",
               now |> Timex.shift(seconds: -20) |> Calendar.strftime("%c.%f %Z")
             )

      assert view |> has_element?("div[id^=ran-for]", "5000 ms")

      assert view |> has_element?("div[id^=exit-code]", "0")
    end

    test "When run A and B are successful but C is pending, work_order status is 'Pending'",
         %{conn: conn, project: project} do
      %{job: job_a, trigger: trigger} =
        workflow_job_fixture(
          project_id: project.id,
          body: ~s[fn(state => { return {...state, extra: "data"} })]
        )

      job_b =
        job_fixture(
          trigger: %{type: :on_job_success, upstream_job_id: job_a.id},
          body: ~s[fn(state => state)],
          workflow_id: job_a.workflow_id
        )

      job_c =
        job_fixture(
          trigger: %{type: :on_job_success, upstream_job_id: job_b.id},
          body: ~s[fn(state => state)],
          workflow_id: job_a.workflow_id
        )

      work_order =
        work_order_fixture(
          project_id: project.id,
          workflow_id: job_a.workflow_id
        )

      dataclip = dataclip_fixture(project_id: project.id)

      reason =
        reason_fixture(
          trigger_id: trigger.id,
          dataclip_id: dataclip.id
        )

      now = Timex.now()

      Attempt.new(%{
        work_order_id: work_order.id,
        reason_id: reason.id,
        runs: [
          %{
            job_id: job_a.id,
            started_at: now |> Timex.shift(seconds: -25),
            finished_at: now |> Timex.shift(seconds: -20),
            exit_code: 0,
            input_dataclip_id: dataclip.id
          },
          %{
            job_id: job_b.id,
            started_at: now |> Timex.shift(seconds: -10),
            finished_at: now |> Timex.shift(seconds: -5),
            exit_code: 0,
            input_dataclip_id: dataclip_fixture(project_id: project.id).id
          },
          %{
            job_id: job_c.id,
            started_at: now |> Timex.shift(seconds: -5),
            # A pending job can't have a finished_at value
            finished_at: nil,
            exit_code: nil,
            input_dataclip_id: dataclip_fixture(project_id: project.id).id
          }
        ]
      })
      |> Lightning.Repo.insert!()

      {:ok, view, _html} =
        live(
          conn,
          Routes.project_run_index_path(conn, :index, job_a.workflow.project_id)
        )

      div =
        view
        |> element(
          "section#inner_content div[data-entity='work_order_list'] > div:first-child > div:last-child"
        )
        |> render()

      assert div =~ "Pending"

      assert view
             |> element(
               "section#inner_content div[data-entity='work_order_list'] > div:first-child button[phx-click='toggle_details']"
             )
             |> render_click() =~ "Pending"
    end
  end

  describe "Search and Filtering" do
    test "Search form is displayed", %{
      conn: conn,
      project: project
    } do
      %{job: job, trigger: trigger} =
        workflow_job_fixture(
          workflow_name: "my workflow",
          project_id: project.id,
          body: ~s[fn(state => { return {...state, extra: "data"} })]
        )

      work_order = work_order_fixture(workflow_id: job.workflow_id)

      dataclip = dataclip_fixture()

      reason =
        reason_fixture(
          trigger_id: trigger.id,
          dataclip_id: dataclip.id
        )

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

      assert html =~ "Filter by workorder status"

      assert view
             |> element("input#run-search-form_success[checked]")
             |> has_element?()

      assert view
             |> element("input#run-search-form_failure[checked]")
             |> has_element?()

      assert view
             |> element("input#run-search-form_timeout[checked]")
             |> has_element?()

      assert view
             |> element("input#run-search-form_crash[checked]")
             |> has_element?()

      assert view
             |> element("input#run-search-form_pending[checked]")
             |> has_element?()

      assert view
             |> element("input#run-search-form_search_term")
             |> has_element?()

      assert view
             |> element("input#run-search-form_body[checked]")
             |> has_element?()

      assert view
             |> element("input#run-search-form_log[checked]")
             |> has_element?()
    end

    test "Run with failure status shows when option checked", %{
      conn: conn,
      project: project
    } do
      %{job: job, trigger: trigger} =
        workflow_job_fixture(
          workflow_name: "my workflow",
          project_id: project.id,
          body: ~s[fn(state => { return {...state, extra: "data"} })]
        )

      work_order = work_order_fixture(workflow_id: job.workflow_id)

      dataclip = dataclip_fixture()

      reason =
        reason_fixture(
          trigger_id: trigger.id,
          dataclip_id: dataclip.id
        )

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
      |> form("#run-search-form", filters: %{"failure" => "false"})
      |> render_submit()

      refute view
             |> element(
               "section#inner_content div[data-entity='work _order_list'] > div:first-child > div:last-child"
             )
             |> has_element?()

      # recheck failure

      view
      |> form("#run-search-form", filters: %{"failure" => "true"})
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
      %{job: job, trigger: trigger} =
        workflow_job_fixture(
          workflow_name: "workflow 1",
          project_id: project.id,
          body: ~s[fn(state => { return {...state, extra: "data"} })]
        )

      work_order = work_order_fixture(workflow_id: job.workflow_id)

      dataclip = dataclip_fixture()

      reason =
        reason_fixture(
          trigger_id: trigger.id,
          dataclip_id: dataclip.id
        )

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
              exit_code: 0,
              input_dataclip_id: dataclip.id
            }
          ]
        })
        |> Lightning.Repo.insert!()

      %{job: job_two, trigger: trigger_two} =
        workflow_job_fixture(
          workflow_name: "workflow 2",
          project_id: project.id,
          body: ~s[fn(state => { return {...state, extra: "data"} })]
        )

      work_order = work_order_fixture(workflow_id: job_two.workflow_id)

      dataclip = dataclip_fixture()

      reason =
        reason_fixture(
          trigger_id: trigger_two.id,
          dataclip_id: dataclip.id
        )

      now = Timex.now()

      %{id: _attempt_id} =
        Attempt.new(%{
          work_order_id: work_order.id,
          reason_id: reason.id,
          runs: [
            %{
              job_id: job_two.id,
              started_at: now |> Timex.shift(seconds: -25),
              finished_at: now |> Timex.shift(seconds: -1),
              exit_code: 1,
              input_dataclip_id: dataclip.id
            }
          ]
        })
        |> Lightning.Repo.insert!()

      %{job: job_other_project} =
        workflow_job_fixture(
          workflow_name: "my workflow",
          project_id: Lightning.ProjectsFixtures.project_fixture().id,
          body: ~s[fn(state => { return {...state, extra: "data"} })]
        )

      {:ok, view, html} =
        live(conn, Routes.project_run_index_path(conn, :index, project.id))

      assert html =~ "Filter by workflow"

      assert view
             |> element("option[value=#{job.workflow_id}]")
             |> has_element?()

      assert view
             |> element("option[value=#{job_two.workflow_id}]")
             |> has_element?()

      refute view
             |> element("option[value=#{job_other_project.workflow_id}]")
             |> has_element?()

      assert view
             |> element("form#run-search-form")
             |> render_submit(%{
               "filters[workflow_id]" => job_two.workflow_id
             })

      div =
        view
        |> element(
          "section#inner_content div[data-entity='work_order_list'] > div:first-child"
        )
        |> render()

      refute div =~ "workflow 1"
      assert div =~ "workflow 2"

      assert view
             |> element("form#run-search-form")
             |> render_submit(%{
               "filters[workflow_id]" => job.workflow_id
             })

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
      %{job: job_one, trigger: trigger} =
        workflow_job_fixture(
          workflow_name: "workflow 1",
          project_id: project.id,
          body: ~s[fn(state => { return {...state, extra: "data"} })]
        )

      work_order = work_order_fixture(workflow_id: job_one.workflow_id)

      dataclip = dataclip_fixture()

      reason =
        reason_fixture(
          trigger_id: trigger.id,
          dataclip_id: dataclip.id
        )

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

      %{job: job_two, trigger: trigger_two} =
        workflow_job_fixture(
          workflow_name: "workflow 2",
          project_id: project.id,
          body: ~s[fn(state => { return {...state, extra: "data"} })]
        )

      work_order = work_order_fixture(workflow_id: job_two.workflow_id)

      dataclip = dataclip_fixture()

      reason =
        reason_fixture(
          trigger_id: trigger_two.id,
          dataclip_id: dataclip.id
        )

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

      assert html =~ expected_d2 |> Timex.format!("{YYYY}-{0M}-{0D}")
      assert html =~ expected_d1 |> Timex.format!("{YYYY}-{0M}-{0D}")

      # set date after to 11 days ago, only see second workorder

      result =
        view
        |> element("form#run-search-form")
        |> render_submit(%{
          "filters[date_after]" => Timex.now() |> Timex.shift(days: -11)
        })

      refute result =~ expected_d1 |> Timex.format!("{YYYY}-{0M}-{0D}")
      assert result =~ expected_d2 |> Timex.format!("{YYYY}-{0M}-{0D}")

      # set date before to 12 days ago, only see first workorder

      # reset after date
      view
      |> element("form#run-search-form")
      |> render_submit(%{"filters[date_after]" => nil})

      result =
        view
        |> element("form#run-search-form")
        |> render_submit(%{
          "filters[date_before]" => Timex.now() |> Timex.shift(days: -12)
        })

      assert result =~ expected_d1 |> Timex.format!("{YYYY}-{0M}-{0D}")
      refute result =~ expected_d2 |> Timex.format!("{YYYY}-{0M}-{0D}")

      # reset before date
      result =
        view
        |> element("form#run-search-form")
        |> render_submit(%{"filters[date_before]" => nil})

      assert result =~ expected_d1 |> Timex.format!("{YYYY}-{0M}-{0D}")
      assert result =~ expected_d2 |> Timex.format!("{YYYY}-{0M}-{0D}")
    end

    test "Filter by run run_log and dataclip_body", %{
      conn: conn,
      project: project
    } do
      # workflow 1 -> 1 run success -> contains body with some data
      # workflow 2 -> 1 run failure -> contains log with some log

      %{job: job_one, trigger: trigger} =
        workflow_job_fixture(
          workflow_name: "workflow 1",
          project_id: project.id,
          body: ~s[fn(state => { return {...state, extra: "data"} })]
        )

      work_order = work_order_fixture(workflow_id: job_one.workflow_id)

      dataclip =
        dataclip_fixture(
          type: :http_request,
          body: %{"username" => "eliaswalyba"}
        )

      reason =
        reason_fixture(
          trigger_id: trigger.id,
          dataclip_id: dataclip.id
        )

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

      %{job: job_two, trigger: trigger_two} =
        workflow_job_fixture(
          workflow_name: "workflow 2",
          project_id: project.id,
          body: ~s[fn(state => { return {...state, extra: "data"} })]
        )

      work_order = work_order_fixture(workflow_id: job_two.workflow_id)

      dataclip =
        dataclip_fixture(type: :http_request, body: %{"username" => "qassim"})

      reason =
        reason_fixture(
          trigger_id: trigger_two.id,
          dataclip_id: dataclip.id
        )

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
      %{job: job} = workflow_job_fixture(project_id: project_scoped.id)
      run = run_fixture(job_id: job.id)

      {:ok, _view, html} =
        live(
          conn,
          Routes.project_run_show_path(conn, :show, project_scoped.id, run.id)
        )

      assert html =~ run.id

      project_unscoped = Lightning.ProjectsFixtures.project_fixture()

      %{job: job} = workflow_job_fixture(project_id: project_scoped.id)
      run = run_fixture(job_id: job.id)

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

      run = run_fixture(started_at: started_at, finished_at: finished_at)

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
      run = run_fixture(started_at: started_at)

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
             |> Floki.text() =~
               ~r/25\d\d\d ms/

      assert html
             |> Floki.find("div#exit-code-#{run.id} > div:nth-child(2)")
             |> Floki.text() =~
               "?"
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
      %{job: job_a, trigger: trigger} =
        workflow_job_fixture(
          project_id: project.id,
          body: ~s[fn(state => { return {...state, extra: "data"} })]
        )

      dataclip = dataclip_fixture(project_id: project.id)

      reason =
        reason_fixture(
          trigger_id: trigger.id,
          dataclip_id: dataclip.id
        )

      work_order =
        work_order_fixture(
          project_id: project.id,
          workflow_id: job_a.workflow_id,
          reason_id: reason.id
        )

      now = Timex.now()

      attempt =
        Attempt.new(%{
          work_order_id: work_order.id,
          reason_id: reason.id,
          runs: [
            %{
              job_id: job_a.id,
              started_at: now |> Timex.shift(seconds: -25),
              finished_at: now |> Timex.shift(seconds: -20),
              exit_code: 0,
              input_dataclip_id: dataclip.id
            }
          ]
        })
        |> Lightning.Repo.insert!()

      %{attempt: attempt, work_order: work_order, project: project}
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

      reason =
        insert(:reason, type: trigger.type, trigger: trigger, dataclip: dataclip)

      work_order_b = insert(:workorder, workflow: workflow, reason: reason)

      now = Timex.now()

      insert(:attempt,
        work_order: work_order_b,
        reason: reason,
        runs: [
          %{
            job: job_b,
            started_at: now |> Timex.shift(seconds: -25),
            finished_at: now |> Timex.shift(seconds: -20),
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

      reason =
        insert(:reason, type: trigger.type, trigger: trigger, dataclip: dataclip)

      work_order_b = insert(:workorder, workflow: workflow, reason: reason)

      now = Timex.now()

      insert(:attempt,
        work_order: work_order_b,
        reason: reason,
        runs: [
          %{
            job: job_b,
            started_at: now |> Timex.shift(seconds: -25),
            finished_at: now |> Timex.shift(seconds: -20),
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

      reason =
        insert(:reason, type: trigger.type, trigger: trigger, dataclip: dataclip)

      work_order_b = insert(:workorder, workflow: workflow, reason: reason)

      now = Timex.now()

      insert(:attempt,
        work_order: work_order_b,
        reason: reason,
        runs: [
          %{
            job: job_b,
            started_at: now |> Timex.shift(seconds: -25),
            finished_at: now |> Timex.shift(seconds: -20),
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

      assert html =~ "whose run Input Body contain TestSearch"

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

      assert html =~ "whose run Input Body and Logs contain TestSearch"

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
      scenario = workflow_scenario(%{project: project})

      work_order_1 =
        work_order_fixture(
          project_id: scenario.project.id,
          workflow_id: scenario.workflow.id
        )

      work_order_2 =
        work_order_fixture(
          project_id: scenario.project.id,
          workflow_id: scenario.workflow.id
        )

      dataclip = dataclip_fixture(project_id: scenario.project.id)

      now = Timex.now()

      attempts =
        Enum.map([work_order_1, work_order_2], fn work_order ->
          runs =
            Enum.map(
              Map.values(scenario.jobs),
              fn j ->
                %{
                  job_id: j.id,
                  started_at: now |> Timex.shift(seconds: -25),
                  finished_at: now |> Timex.shift(seconds: -20),
                  exit_code: 0,
                  input_dataclip_id: dataclip.id
                }
              end
            )

          Attempt.new(%{
            work_order_id: work_order.id,
            reason_id: work_order.reason_id,
            runs: runs
          })
          |> Lightning.Repo.insert!()
        end)

      Map.merge(scenario, %{
        attempts: attempts,
        work_order_1: work_order_1,
        work_order_2: work_order_2
      })
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

      reason =
        insert(:reason, type: trigger.type, trigger: trigger, dataclip: dataclip)

      work_order_3 = insert(:workorder, workflow: workflow, reason: reason)

      now = Timex.now()

      # Attempt 3
      Attempt.new(%{
        work_order_id: work_order_3.id,
        reason_id: reason.id,
        runs: [
          %{
            job_id: job_a.id,
            started_at: now |> Timex.shift(seconds: -25),
            finished_at: now |> Timex.shift(seconds: -20),
            exit_code: 0,
            input_dataclip_id: dataclip.id
          }
        ]
      })
      |> Lightning.Repo.insert!()

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
      jobs: jobs
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

      assert render_click(view, "bulk-rerun", %{type: "all", job: jobs.b.id}) =~
               "You are not authorized to perform this action."
    end

    @tag role: :editor
    test "Project editors can rerun runs", %{
      conn: conn,
      project: project,
      jobs: jobs,
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
      |> render_change(%{job: jobs.a.id})

      result = view |> render_click("bulk-rerun", %{type: "all", job: jobs.a.id})

      {:ok, view, html} = follow_redirect(result, conn)

      assert html =~
               "New attempts enqueued for 2 workorders"

      view
      |> form("##{work_order_1.id}-selection-form")
      |> render_change(%{selected: true})

      view
      |> form("#select-job-for-rerun-form")
      |> render_change(%{job: jobs.a.id})

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
      dataclip = dataclip_fixture(project_id: project.id)

      now = Timex.now()

      scenarios =
        Enum.map(1..3, fn _n ->
          workflow = workflow_fixture(project_id: project.id)

          work_order =
            work_order_fixture(
              project_id: project.id,
              workflow_id: workflow.id
            )

          jobs =
            Enum.map(1..5, fn i ->
              job_fixture(
                name: "job_#{i}",
                workflow_id: workflow.id,
                trigger: %{type: :webhook}
              )
            end)

          runs =
            Enum.map(
              jobs,
              fn j ->
                %{
                  job_id: j.id,
                  started_at: now |> Timex.shift(seconds: -25),
                  finished_at: now |> Timex.shift(seconds: -20),
                  exit_code: 0,
                  input_dataclip_id: dataclip.id
                }
              end
            )

          Attempt.new(%{
            work_order_id: work_order.id,
            reason_id: work_order.reason_id,
            runs: runs
          })
          |> Lightning.Repo.insert!()

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

      for job <- Map.values(jobs) do
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
end
