defmodule LightningWeb.WorkflowControllerTest do
  use LightningWeb.ConnCase, async: true

  import Lightning.Factories

  describe "POST /projects/:project_id/workflows/:workflow_id/runs" do
    setup do
      user = insert(:user)
      project = insert(:project, project_users: [%{user: user}])
      workflow = insert(:workflow, project: project) |> with_snapshot()
      job = insert(:job, workflow: workflow)

      %{
        user: user,
        project: project,
        workflow: workflow,
        job: job,
        conn: build_conn() |> log_in_user(user)
      }
    end

    test "creates manual run from job with custom body", %{
      conn: conn,
      project: project,
      workflow: workflow,
      job: job
    } do
      conn =
        post(conn, ~p"/projects/#{project}/workflows/#{workflow}/runs", %{
          job_id: job.id,
          custom_body: "{\"data\": \"test\"}"
        })

      assert %{
               "data" => %{
                 "workorder_id" => workorder_id,
                 "run_id" => run_id,
                 "dataclip" => dataclip
               }
             } = json_response(conn, 201)

      assert is_binary(workorder_id)
      assert is_binary(run_id)
      assert is_map(dataclip)
    end

    test "creates manual run from job with empty input", %{
      conn: conn,
      project: project,
      workflow: workflow,
      job: job
    } do
      conn =
        post(conn, ~p"/projects/#{project}/workflows/#{workflow}/runs", %{
          job_id: job.id
        })

      assert %{"data" => %{"run_id" => _}} = json_response(conn, 201)
    end

    test "creates manual run from trigger with existing dataclip", %{
      conn: conn,
      project: project
    } do
      workflow = insert(:workflow, project: project) |> with_snapshot()
      trigger = insert(:trigger, workflow: workflow, type: :webhook)
      job = insert(:job, workflow: workflow)

      insert(:edge,
        workflow: workflow,
        source_trigger_id: trigger.id,
        target_job_id: job.id
      )

      dataclip = insert(:dataclip, project: project, type: :http_request)

      conn =
        post(conn, ~p"/projects/#{project}/workflows/#{workflow}/runs", %{
          trigger_id: trigger.id,
          dataclip_id: dataclip.id
        })

      assert %{"data" => %{"run_id" => _}} = json_response(conn, 201)
    end

    test "creates manual run from trigger without dataclip", %{
      conn: conn,
      project: project
    } do
      workflow = insert(:workflow, project: project) |> with_snapshot()
      trigger = insert(:trigger, workflow: workflow, type: :webhook)
      job = insert(:job, workflow: workflow)

      insert(:edge,
        workflow: workflow,
        source_trigger_id: trigger.id,
        target_job_id: job.id
      )

      conn =
        post(conn, ~p"/projects/#{project}/workflows/#{workflow}/runs", %{
          trigger_id: trigger.id
        })

      assert %{"data" => %{"run_id" => _}} = json_response(conn, 201)
    end

    test "requires authentication", %{
      project: project,
      workflow: workflow,
      job: job
    } do
      conn = build_conn()

      conn =
        post(conn, ~p"/projects/#{project}/workflows/#{workflow}/runs", %{
          job_id: job.id
        })

      assert redirected_to(conn) == ~p"/users/log_in"
    end

    test "requires edit_workflow permission", %{
      conn: conn
    } do
      # Create a project where user doesn't have access
      other_user = insert(:user)
      viewer_project = insert(:project, project_users: [%{user: other_user}])

      viewer_workflow =
        insert(:workflow, project: viewer_project) |> with_snapshot()

      viewer_job = insert(:job, workflow: viewer_workflow)

      conn =
        post(
          conn,
          ~p"/projects/#{viewer_project}/workflows/#{viewer_workflow}/runs",
          %{
            job_id: viewer_job.id
          }
        )

      # Returns 403 because permission check fails
      assert html_response(conn, 403) =~ "Forbidden"
    end

    test "returns 404 when job not found", %{
      conn: conn,
      project: project,
      workflow: workflow
    } do
      non_existent_job_id = Ecto.UUID.generate()

      conn =
        post(conn, ~p"/projects/#{project}/workflows/#{workflow}/runs", %{
          job_id: non_existent_job_id
        })

      assert html_response(conn, 404)
    end

    test "returns 404 when trigger not found", %{
      conn: conn,
      project: project,
      workflow: workflow
    } do
      non_existent_trigger_id = Ecto.UUID.generate()

      conn =
        post(conn, ~p"/projects/#{project}/workflows/#{workflow}/runs", %{
          trigger_id: non_existent_trigger_id
        })

      assert html_response(conn, 404)
    end

    test "returns 404 when trigger has no connected job", %{
      conn: conn,
      project: project,
      workflow: workflow
    } do
      trigger = insert(:trigger, workflow: workflow, type: :webhook)
      # No edge connecting trigger to a job

      conn =
        post(conn, ~p"/projects/#{project}/workflows/#{workflow}/runs", %{
          trigger_id: trigger.id
        })

      assert html_response(conn, 404)
    end

    test "returns 400 when neither job_id nor trigger_id provided", %{
      conn: conn,
      project: project,
      workflow: workflow
    } do
      conn =
        post(conn, ~p"/projects/#{project}/workflows/#{workflow}/runs", %{})

      # Returns 400 HTML error
      assert html_response(conn, 400) =~ "Bad Request"
    end
  end
end
