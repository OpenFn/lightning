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

  describe "GET /projects/:project_id/runs/:run_id/steps" do
    setup do
      user = insert(:user)
      project = insert(:project, project_users: [%{user: user}])
      workflow = insert(:workflow, project: project) |> with_snapshot()
      job = insert(:job, workflow: workflow)

      dataclip = insert(:dataclip, project: project)
      workorder = insert(:workorder, workflow: workflow)

      run =
        insert(:run,
          work_order: workorder,
          dataclip: dataclip,
          starting_job: job
        )

      step = insert(:step, job: job, input_dataclip: dataclip, runs: [run])

      %{
        user: user,
        project: project,
        workflow: workflow,
        job: job,
        run: run,
        step: step,
        dataclip: dataclip,
        conn: build_conn() |> log_in_user(user)
      }
    end

    test "returns step data for a run and job", %{
      conn: conn,
      project: project,
      run: run,
      job: job,
      step: step,
      dataclip: dataclip
    } do
      conn =
        get(conn, ~p"/projects/#{project}/runs/#{run}/steps?job_id=#{job.id}")

      assert %{
               "data" => %{
                 "id" => step_id,
                 "input_dataclip_id" => input_dataclip_id,
                 "job_id" => job_id
               }
             } = json_response(conn, 200)

      assert step_id == step.id
      assert input_dataclip_id == dataclip.id
      assert job_id == job.id
    end

    test "returns 404 when step not found for job", %{
      conn: conn,
      project: project,
      run: run
    } do
      other_job = insert(:job)

      conn =
        get(
          conn,
          ~p"/projects/#{project}/runs/#{run}/steps?job_id=#{other_job.id}"
        )

      assert %{"error" => "Step not found for the specified job"} =
               json_response(conn, 404)
    end

    test "returns 400 when job_id missing", %{
      conn: conn,
      project: project,
      run: run
    } do
      conn = get(conn, ~p"/projects/#{project}/runs/#{run}/steps")

      assert %{"error" => "Missing required parameters: job_id"} =
               json_response(conn, 400)
    end

    test "requires authentication", %{
      project: project,
      run: run,
      job: job
    } do
      conn = build_conn()

      conn =
        get(conn, ~p"/projects/#{project}/runs/#{run}/steps?job_id=#{job.id}")

      assert redirected_to(conn) == ~p"/users/log_in"
    end

    test "requires project access", %{
      run: run,
      job: job
    } do
      other_user = insert(:user)
      other_project = insert(:project, project_users: [%{user: other_user}])

      conn = build_conn() |> log_in_user(other_user)

      conn =
        get(
          conn,
          ~p"/projects/#{other_project}/runs/#{run}/steps?job_id=#{job.id}"
        )

      assert html_response(conn, 403) =~ "Forbidden"
    end
  end

  describe "POST /projects/:project_id/runs/:run_id/retry" do
    setup do
      user = insert(:user)
      project = insert(:project, project_users: [%{user: user}])
      workflow = insert(:workflow, project: project) |> with_snapshot()
      job = insert(:job, workflow: workflow)

      dataclip = insert(:dataclip, project: project)
      workorder = insert(:workorder, workflow: workflow)

      run =
        insert(:run,
          work_order: workorder,
          dataclip: dataclip,
          starting_job: job
        )

      step = insert(:step, job: job, input_dataclip: dataclip, runs: [run])

      %{
        user: user,
        project: project,
        workflow: workflow,
        job: job,
        run: run,
        step: step,
        dataclip: dataclip,
        conn: build_conn() |> log_in_user(user)
      }
    end

    test "retries a run successfully", %{
      conn: conn,
      project: project,
      run: run,
      step: step
    } do
      conn =
        post(conn, ~p"/projects/#{project}/runs/#{run}/retry", %{
          step_id: step.id
        })

      assert %{"data" => %{"run_id" => new_run_id}} = json_response(conn, 201)
      assert is_binary(new_run_id)
      assert new_run_id != run.id
    end

    test "returns 400 when step_id missing", %{
      conn: conn,
      project: project,
      run: run
    } do
      conn = post(conn, ~p"/projects/#{project}/runs/#{run}/retry", %{})

      assert %{"error" => "Missing required parameters: step_id"} =
               json_response(conn, 400)
    end

    test "returns 422 when dataclip is wiped", %{
      conn: conn,
      project: project,
      run: run,
      step: step,
      dataclip: dataclip
    } do
      # Wipe the dataclip
      wiped_at = DateTime.utc_now() |> DateTime.truncate(:second)

      dataclip
      |> Ecto.Changeset.change(%{wiped_at: wiped_at})
      |> Lightning.Repo.update!()

      conn =
        post(conn, ~p"/projects/#{project}/runs/#{run}/retry", %{
          step_id: step.id
        })

      response = json_response(conn, 422)
      assert %{"error" => "Failed to retry run"} = response
    end

    test "returns 422 when workflow is deleted", %{
      conn: conn,
      project: project,
      run: run,
      step: step,
      workflow: workflow
    } do
      # Mark workflow as deleted
      deleted_at = DateTime.utc_now() |> DateTime.truncate(:second)

      workflow
      |> Ecto.Changeset.change(%{deleted_at: deleted_at})
      |> Lightning.Repo.update!()

      conn =
        post(conn, ~p"/projects/#{project}/runs/#{run}/retry", %{
          step_id: step.id
        })

      assert %{"error" => "Cannot retry run for deleted workflow"} =
               json_response(conn, 422)
    end

    test "requires authentication", %{
      project: project,
      run: run,
      step: step
    } do
      conn = build_conn()

      conn =
        post(conn, ~p"/projects/#{project}/runs/#{run}/retry", %{
          step_id: step.id
        })

      assert redirected_to(conn) == ~p"/users/log_in"
    end

    test "requires run_workflow permission", %{
      run: run,
      step: step
    } do
      other_user = insert(:user)
      other_project = insert(:project, project_users: [%{user: other_user}])

      conn = build_conn() |> log_in_user(other_user)

      conn =
        post(conn, ~p"/projects/#{other_project}/runs/#{run}/retry", %{
          step_id: step.id
        })

      # Verify forbidden response (can be JSON error from FallbackController)
      assert conn.status == 422
      response = json_response(conn, 422)
      assert response["error"] =~ "forbidden"
    end

    test "returns 422 when run does not exist", %{
      conn: conn,
      project: project,
      step: step
    } do
      fake_run_id = Ecto.UUID.generate()

      conn =
        post(conn, ~p"/projects/#{project}/runs/#{fake_run_id}/retry", %{
          step_id: step.id
        })

      assert conn.status == 422
      response = json_response(conn, 422)
      assert response["error"] =~ "not_found"
    end
  end
end
