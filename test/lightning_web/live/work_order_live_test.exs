defmodule LightningWeb.RunWorkOrderTest do
  use LightningWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Lightning.Pipeline
  alias Lightning.{Attempt, AttemptRun}
  alias Lightning.Invocation.{Run}

  import Lightning.JobsFixtures
  import Lightning.InvocationFixtures
  import Lightning.CredentialsFixtures

  setup :register_and_log_in_user
  setup :create_project_for_current_user

  describe "Index" do

    test "When run A,B and C are successful, workflow run status is 'Success'", %{conn: conn, project: project} do
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

      {:ok, attempt_run} =
        AttemptRun.new()
        |> Ecto.Changeset.put_assoc(
          :attempt,
          Attempt.changeset(%Attempt{}, %{
            work_order_id: work_order.id,
            reason_id: reason.id
          })
        )
        |> Ecto.Changeset.put_assoc(
          :run,
          Run.changeset(%Run{}, %{
            project_id: job_a.workflow.project_id,
            job_id: job_a.id,
            input_dataclip_id: dataclip.id
          })
        )
        |> Lightning.Repo.insert()

      Pipeline.process(attempt_run)

      {:ok, view, _html} =
        live(conn, Routes.project_run_index_path(conn, :index, job_a.workflow.project_id))

      td = view |> element("section#inner_content tr > td:last-child") |> render()
      assert td =~ "Success"
    end

    test "When run A and B are successful but C fails, workflow run status is 'Failure'", %{conn: conn, project: project} do
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

      {:ok, attempt_run} =
        AttemptRun.new()
        |> Ecto.Changeset.put_assoc(
          :attempt,
          Attempt.changeset(%Attempt{}, %{
            work_order_id: work_order.id,
            reason_id: reason.id
          })
        )
        |> Ecto.Changeset.put_assoc(
          :run,
          Run.changeset(%Run{}, %{
            project_id: job_a.workflow.project_id,
            job_id: job_a.id,
            input_dataclip_id: dataclip.id
          })
        )
        |> Lightning.Repo.insert()

      Pipeline.process(attempt_run)

      {:ok, view, _html} =
        live(conn, Routes.project_run_index_path(conn, :index, job_a.workflow.project_id))

      td = view |> element("section#inner_content tr > td:last-child") |> render()
      assert td =~ "Failure"
    end

    test "When run A times out, workflow run status is 'Timeout'", %{conn: conn, project: project} do
      # job_a =
      #   workflow_job_fixture(
      #     project_id: project.id,
      #     body: ~s[fn(state => {  setTimeout(() => {}, 20000) })]
      #     # body: ~s[fn(state => { return {...state, extra: "data"} })]
      #   )

      # job_b =
      #   job_fixture(
      #     name: "job_b",
      #     trigger: %{type: :on_job_success, upstream_job_id: job_a.id},
      #     body: ~s[fn(state => state)],
      #     workflow_id: job_a.workflow_id,
      #     project_credential_id:
      #       project_credential_fixture(
      #         name: "my credential",
      #         body: %{"credential" => "body"}
      #       ).id
      #   )

      # job_fixture(
      #   name: "job_c",
      #     trigger: %{type: :on_job_success, upstream_job_id: job_b.id},
      #     body: ~s[fn(state => state)],
      #     workflow_id: job_a.workflow_id,
      #     project_credential_id:
      #       project_credential_fixture(
      #         name: "my credential",
      #         body: %{"credential" => "body"}
      #       ).id
      #   )

      # work_order = work_order_fixture(workflow_id: job_a.workflow_id)

      # dataclip = dataclip_fixture()

      # reason =
      #   reason_fixture(
      #     trigger_id: job_a.trigger.id,
      #     dataclip_id: dataclip.id
      #   )

      # {:ok, attempt_run} =
      #   AttemptRun.new()
      #   |> Ecto.Changeset.put_assoc(
      #     :attempt,
      #     Attempt.changeset(%Attempt{}, %{
      #       work_order_id: work_order.id,
      #       reason_id: reason.id
      #     })
      #   )
      #   |> Ecto.Changeset.put_assoc(
      #     :run,
      #     Run.changeset(%Run{}, %{
      #       project_id: job_a.workflow.project_id,
      #       job_id: job_a.id,
      #       input_dataclip_id: dataclip.id,
      #       exit_code: 2
      #     })
      #   )
      #   |> Lightning.Repo.insert()

      # Pipeline.process(attempt_run)

      # {:ok, view, _html} =
      #   live(conn, Routes.project_run_index_path(conn, :index, job_a.workflow.project_id))

      # td = view |> element("section#inner_content tr > td:last-child") |> render() |> IO.inspect()
      # assert td =~ "Timeout"

    end
  end
end
