defmodule LightningWeb.RunWorkOrderTest do
  use LightningWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Lightning.Attempt

  import Lightning.JobsFixtures
  import Lightning.InvocationFixtures
  import Lightning.CredentialsFixtures

  setup :register_and_log_in_user
  setup :create_project_for_current_user

  describe "Index" do
    test "lists all workorders", %{
      conn: conn,
      project: project
    } do
      job =
        workflow_job_fixture(
          workflow_name: "my workflow",
          project_id: project.id,
          body: ~s[fn(state => { return {...state, extra: "data"} })]
        )

      work_order = work_order_fixture(workflow_id: job.workflow_id)

      dataclip = dataclip_fixture()

      reason =
        reason_fixture(
          trigger_id: job.trigger.id,
          dataclip_id: dataclip.id
        )

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

      assert html =~ "Runs"

      table =
        view
        |> element("section#inner_content div[data-entity='work_order_index']")
        |> render()

      assert table =~ "my workflow"
      assert table =~ "#{work_order.reason_id}"

      # toggle work_order details
      # TODO move to test work_order_component

      assert view
             |> element(
               "section#inner_content div[data-entity='work_order_list'] > div:first-child button[phx-click='toggle-details']"
             )
             |> render_click() =~ "attempt-#{attempt_id}"

      refute view
             |> element(
               "section#inner_content div[data-entity='work_order_list'] > div:first-child button[phx-click='toggle-details']"
             )
             |> render_click() =~ "attempt-#{attempt_id}"
    end

    test "When the most recent run is not complete, workflow run status is 'Pending'",
         %{conn: conn, project: project} do
      job_a =
        workflow_job_fixture(
          project_id: project.id,
          body: ~s[fn(state => { return {...state, extra: "data"} })]
        )

      work_order = work_order_fixture(workflow_id: job_a.workflow_id)

      dataclip = dataclip_fixture()

      reason =
        reason_fixture(
          trigger_id: job_a.trigger.id,
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
        |> element(
          "section#inner_content div[data-entity='work_order_list'] > div:first-child > div:last-child"
        )
        |> render()

      assert div =~ "Pending"
    end

    test "When run A,B and C are successful, workflow run status is 'Success'",
         %{conn: conn, project: project} do
      job_a =
        workflow_job_fixture(
          project_id: project.id,
          body: ~s[fn(state => { return {...state, extra: "data"} })]
        )

      job_b =
        job_fixture(
          trigger: %{type: :on_job_success, upstream_job_id: job_a.id},
          body: ~s[fn(state => state)],
          workflow_id: job_a.workflow_id,
          project_credential_id:
            project_credential_fixture(
              name: "my credential",
              body: %{"credential" => "body"}
            ).id
        )

      job_c =
        job_fixture(
          trigger: %{type: :on_job_success, upstream_job_id: job_b.id},
          body: ~s[fn(state => state)],
          workflow_id: job_a.workflow_id,
          project_credential_id:
            project_credential_fixture(
              name: "my credential",
              body: %{"credential" => "body"}
            ).id
        )

      work_order = work_order_fixture(workflow_id: job_a.workflow_id)

      dataclip = dataclip_fixture()

      reason =
        reason_fixture(
          trigger_id: job_a.trigger.id,
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
            input_dataclip_id: dataclip.id
          },
          %{
            job_id: job_c.id,
            started_at: now |> Timex.shift(seconds: -5),
            finished_at: now |> Timex.shift(seconds: -1),
            exit_code: 0,
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
        |> element(
          "section#inner_content div[data-entity='work_order_list'] > div:first-child > div:last-child"
        )
        |> render()

      assert div =~ "Success"
    end

    test "When run A and B are successful but C fails, workflow run status is 'Failure'",
         %{conn: conn, project: project} do
      job_a =
        workflow_job_fixture(
          project_id: project.id,
          body: ~s[fn(state => { return {...state, extra: "data"} })]
        )

      job_b =
        job_fixture(
          trigger: %{type: :on_job_success, upstream_job_id: job_a.id},
          body: ~s[fn(state => state)],
          workflow_id: job_a.workflow_id,
          project_credential_id:
            project_credential_fixture(
              name: "my credential",
              body: %{"credential" => "body"}
            ).id
        )

      job_c =
        job_fixture(
          trigger: %{type: :on_job_success, upstream_job_id: job_b.id},
          body: ~s[fn(state => { throw new Error("I'm supposed to fail.") })],
          workflow_id: job_a.workflow_id,
          project_credential_id:
            project_credential_fixture(
              name: "my credential",
              body: %{"credential" => "body"}
            ).id
        )

      work_order = work_order_fixture(workflow_id: job_a.workflow_id)

      dataclip = dataclip_fixture()

      reason =
        reason_fixture(
          trigger_id: job_a.trigger.id,
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
            exit_code: 1,
            input_dataclip_id: dataclip.id
          },
          %{
            job_id: job_c.id,
            started_at: now |> Timex.shift(seconds: -5),
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
          Routes.project_run_index_path(conn, :index, job_a.workflow.project_id)
        )

      div =
        view
        |> element(
          "section#inner_content div[data-entity='work_order_list'] > div:first-child > div:last-child"
        )
        |> render()

      assert div =~ "Failure"

      assert view
             |> element(
               "section#inner_content div[data-entity='work_order_list'] > div:first-child button[phx-click='toggle-details']"
             )
             |> render_click() =~ "Failure"
    end
  end
end
