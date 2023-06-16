defmodule LightningWeb.RunWorkOrderTest do
  use LightningWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Lightning.Attempt

  import Lightning.JobsFixtures
  import Lightning.InvocationFixtures

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

      {:ok, view, html} =
        live(
          conn,
          Routes.project_run_index_path(conn, :index, project.id)
        )
        |> follow_redirect(
          conn,
          "/projects/#{project.id}/runs?filters[body]=true&filters[crash]=true&filters[date_after]=&filters[date_before]=&filters[failure]=true&filters[log]=true&filters[pending]=true&filters[search_term]=&filters[success]=true&filters[timeout]=true&filters[wo_date_after]=&filters[wo_date_before]=&filters[workflow_id]=&project_id=#{project.id}"
        )

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
        |> follow_redirect(
          conn,
          "/projects/#{job_a.workflow.project_id}/runs?filters[body]=true&filters[crash]=true&filters[date_after]=&filters[date_before]=&filters[failure]=true&filters[log]=true&filters[pending]=true&filters[search_term]=&filters[success]=true&filters[timeout]=true&filters[wo_date_after]=&filters[wo_date_before]=&filters[workflow_id]=&project_id=#{job_a.workflow.project_id}"
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
        |> follow_redirect(
          conn,
          "/projects/#{job_a.workflow.project_id}/runs?filters[body]=true&filters[crash]=true&filters[date_after]=&filters[date_before]=&filters[failure]=true&filters[log]=true&filters[pending]=true&filters[search_term]=&filters[success]=true&filters[timeout]=true&filters[wo_date_after]=&filters[wo_date_before]=&filters[workflow_id]=&project_id=#{job_a.workflow.project_id}"
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
        |> follow_redirect(
          conn,
          "/projects/#{job_a.workflow.project_id}/runs?filters[body]=true&filters[crash]=true&filters[date_after]=&filters[date_before]=&filters[failure]=true&filters[log]=true&filters[pending]=true&filters[search_term]=&filters[success]=true&filters[timeout]=true&filters[wo_date_after]=&filters[wo_date_before]=&filters[workflow_id]=&project_id=#{job_a.workflow.project_id}"
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
        |> follow_redirect(
          conn,
          "/projects/#{job_a.workflow.project_id}/runs?filters[body]=true&filters[crash]=true&filters[date_after]=&filters[date_before]=&filters[failure]=true&filters[log]=true&filters[pending]=true&filters[search_term]=&filters[success]=true&filters[timeout]=true&filters[wo_date_after]=&filters[wo_date_before]=&filters[workflow_id]=&project_id=#{job_a.workflow.project_id}"
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
        |> follow_redirect(
          conn,
          "/projects/#{job_a.workflow.project_id}/runs?filters[body]=true&filters[crash]=true&filters[date_after]=&filters[date_before]=&filters[failure]=true&filters[log]=true&filters[pending]=true&filters[search_term]=&filters[success]=true&filters[timeout]=true&filters[wo_date_after]=&filters[wo_date_before]=&filters[workflow_id]=&project_id=#{job_a.workflow.project_id}"
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
        live(
          conn,
          Routes.project_run_index_path(conn, :index, project.id)
        )
        |> follow_redirect(
          conn,
          "/projects/#{project.id}/runs?filters[body]=true&filters[crash]=true&filters[date_after]=&filters[date_before]=&filters[failure]=true&filters[log]=true&filters[pending]=true&filters[search_term]=&filters[success]=true&filters[timeout]=true&filters[wo_date_after]=&filters[wo_date_before]=&filters[workflow_id]=&project_id=#{project.id}"
        )

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
        live(
          conn,
          Routes.project_run_index_path(conn, :index, project.id)
        )
        |> follow_redirect(
          conn,
          "/projects/#{project.id}/runs?filters[body]=true&filters[crash]=true&filters[date_after]=&filters[date_before]=&filters[failure]=true&filters[log]=true&filters[pending]=true&filters[search_term]=&filters[success]=true&filters[timeout]=true&filters[wo_date_after]=&filters[wo_date_before]=&filters[workflow_id]=&project_id=#{project.id}"
        )

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
        live(
          conn,
          Routes.project_run_index_path(conn, :index, project.id)
        )
        |> follow_redirect(
          conn,
          "/projects/#{project.id}/runs?filters[body]=true&filters[crash]=true&filters[date_after]=&filters[date_before]=&filters[failure]=true&filters[log]=true&filters[pending]=true&filters[search_term]=&filters[success]=true&filters[timeout]=true&filters[wo_date_after]=&filters[wo_date_before]=&filters[workflow_id]=&project_id=#{project.id}"
        )

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

      %{id: _attempt_id} =
        Attempt.new(%{
          work_order_id: work_order.id,
          reason_id: reason.id,
          runs: [
            %{
              job_id: job_one.id,
              started_at:
                DateTime.from_naive!(~N[2022-08-23 00:00:10.123456], "Etc/UTC"),
              finished_at:
                DateTime.from_naive!(~N[2022-08-23 00:50:10.123456], "Etc/UTC"),
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

      %{id: _attempt_id} =
        Attempt.new(%{
          work_order_id: work_order.id,
          reason_id: reason.id,
          runs: [
            %{
              job_id: job_two.id,
              started_at:
                DateTime.from_naive!(~N[2022-08-29 00:00:10.123456], "Etc/UTC"),
              finished_at:
                DateTime.from_naive!(~N[2022-08-29 00:00:10.123456], "Etc/UTC"),
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
        |> follow_redirect(
          conn,
          "/projects/#{project.id}/runs?filters[body]=true&filters[crash]=true&filters[date_after]=&filters[date_before]=&filters[failure]=true&filters[log]=true&filters[pending]=true&filters[search_term]=&filters[success]=true&filters[timeout]=true&filters[wo_date_after]=&filters[wo_date_before]=&filters[workflow_id]=&project_id=#{project.id}"
        )

      assert html =~ "2022-08-23"
      assert html =~ "2022-08-29"

      # set date after to 2022-08-25

      result =
        view
        |> element("form#run-search-form")
        |> render_submit(%{
          "filters[date_after]" => ~N[2022-08-25 00:00:00.123456]
        })

      assert result =~ "2022-08-29"
      refute result =~ "2022-08-23"

      # set date before to 2022-08-28

      # reset after date
      view
      |> element("form#run-search-form")
      |> render_submit(%{"filters[date_after]" => nil})

      result =
        view
        |> element("form#run-search-form")
        |> render_submit(%{
          "filters[date_before]" => ~N[2022-08-28 00:00:00.123456]
        })

      assert result =~ "2022-08-23"
      refute result =~ "2022-08-29"

      # reset before date
      result =
        view
        |> element("form#run-search-form")
        |> render_submit(%{"filters[date_before]" => nil})

      assert result =~ "2022-08-23"
      assert result =~ "2022-08-29"
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

      %{id: _attempt_id} =
        Attempt.new(%{
          work_order_id: work_order.id,
          reason_id: reason.id,
          runs: [
            %{
              job_id: job_one.id,
              started_at:
                DateTime.from_naive!(~N[2022-08-23 00:00:10.123456], "Etc/UTC"),
              finished_at:
                DateTime.from_naive!(~N[2022-08-23 00:50:10.123456], "Etc/UTC"),
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

      %{id: _attempt_id} =
        Attempt.new(%{
          work_order_id: work_order.id,
          reason_id: reason.id,
          runs: [
            %{
              job_id: job_two.id,
              started_at:
                DateTime.from_naive!(~N[2022-08-29 00:00:10.123456], "Etc/UTC"),
              finished_at:
                DateTime.from_naive!(~N[2022-08-29 00:00:10.123456], "Etc/UTC"),
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
        live(
          conn,
          Routes.project_run_index_path(conn, :index, project.id)
        )
        |> follow_redirect(
          conn,
          "/projects/#{project.id}/runs?filters[body]=true&filters[crash]=true&filters[date_after]=&filters[date_before]=&filters[failure]=true&filters[log]=true&filters[pending]=true&filters[search_term]=&filters[success]=true&filters[timeout]=true&filters[wo_date_after]=&filters[wo_date_before]=&filters[workflow_id]=&project_id=#{project.id}"
        )

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
        render_component(&LightningWeb.RunLive.Components.run_details/1, run: run)
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
        render_component(&LightningWeb.RunLive.Components.run_details/1, run: run)
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

  describe "rerun" do
    test "Project editors can rerun runs",
         %{conn: conn, project: project} do
      {conn, _user} = setup_project_user(conn, project, :editor)

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

      run =
        Map.get(attempt, :runs)
        |> List.first()

      Lightning.Invocation.search_workorders(project).entries()

      {:ok, view, _html} =
        live(
          conn,
          Routes.project_run_index_path(conn, :index, job_a.workflow.project_id)
        )
        |> follow_redirect(
          conn,
          "/projects/#{job_a.workflow.project_id}/runs?filters[body]=true&filters[crash]=true&filters[date_after]=&filters[date_before]=&filters[failure]=true&filters[log]=true&filters[pending]=true&filters[search_term]=&filters[success]=true&filters[timeout]=true&filters[wo_date_after]=&filters[wo_date_before]=&filters[workflow_id]=&project_id=#{job_a.workflow.project_id}"
        )

      assert view
             |> render_click("rerun", %{
               "attempt_id" => attempt.id,
               "run_id" => run.id
             })
    end

    test "Project viewers can't rerun runs",
         %{conn: conn, project: project} do
      {conn, _user} = setup_project_user(conn, project, :viewer)

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

      run =
        Map.get(attempt, :runs)
        |> List.first()

      Lightning.Invocation.search_workorders(project).entries()

      {:ok, view, _html} =
        live(
          conn,
          Routes.project_run_index_path(conn, :index, job_a.workflow.project_id)
        )
        |> follow_redirect(
          conn,
          "/projects/#{job_a.workflow.project_id}/runs?filters[body]=true&filters[crash]=true&filters[date_after]=&filters[date_before]=&filters[failure]=true&filters[log]=true&filters[pending]=true&filters[search_term]=&filters[success]=true&filters[timeout]=true&filters[wo_date_after]=&filters[wo_date_before]=&filters[workflow_id]=&project_id=#{job_a.workflow.project_id}"
        )

      assert view
             |> render_click("rerun", %{
               "attempt_id" => attempt.id,
               "run_id" => run.id
             }) =~
               "You are not authorized to perform this action."
    end
  end
end
