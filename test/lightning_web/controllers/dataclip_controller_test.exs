defmodule LightningWeb.DataclipControllerTest do
  use LightningWeb.ConnCase
  import Lightning.Factories

  defp create_steps_dataclips(_context) do
    user = insert(:user)
    project = insert(:project, project_users: [%{user: user}])

    credential1 =
      insert(:credential,
        name: "My Credential1",
        body: %{
          secret: "55"
        },
        user: user
      )

    credential2 =
      insert(:credential,
        name: "My Credential2",
        body: %{
          pin: 123_456,
          looks_like_a_number: "789"
        },
        user: user
      )

    credential3 =
      insert(:credential,
        name: "My Credential3",
        body: %{
          foo: "bar"
        },
        user: user
      )

    project_credential1 =
      insert(:project_credential, credential: credential1, project: project)

    project_credential2 =
      insert(:project_credential, credential: credential2, project: project)

    project_credential3 =
      insert(:project_credential, credential: credential3, project: project)

    workflow = insert(:workflow, project: project)
    trigger = insert(:trigger, workflow: workflow)

    job1 =
      insert(:job, project_credential: project_credential1, workflow: workflow)

    job2 =
      insert(:job, project_credential: project_credential2, workflow: workflow)

    job3 =
      insert(:job, project_credential: project_credential3, workflow: workflow)

    output_dataclip =
      insert(:dataclip,
        project: project,
        type: :step_result,
        body: %{
          integer: 123_456,
          another_no: 789,
          third_no: 125_534,
          map: %{list: [%{"any-key" => "some-bars"}]},
          bool: true,
          foo: "bar"
        }
      )

    input_dataclip = insert(:dataclip)

    now = DateTime.utc_now()

    step1 = insert(:step, job: job1, started_at: now)

    step2 =
      insert(:step,
        exit_reason: "success",
        job: job2,
        input_dataclip: input_dataclip,
        output_dataclip: output_dataclip,
        started_at: DateTime.add(now, 1, :microsecond)
      )

    step3 =
      insert(:step, job: job3, started_at: DateTime.add(now, 2, :microsecond))

    run =
      insert(:run,
        work_order:
          build(:workorder,
            workflow: workflow,
            dataclip: input_dataclip,
            trigger: trigger,
            state: :success
          ),
        starting_trigger: trigger,
        state: :success,
        dataclip: input_dataclip,
        steps: [step1, step2]
      )

    insert(:run_step, run: run, step: step1)
    insert(:run_step, run: run, step: step2)
    insert(:run_step, run: run, step: step3)

    %{
      run: run,
      output_dataclip: output_dataclip,
      job: job2,
      step2: step2,
      user: user
    }
  end

  describe "GET /dataclip/body/:id" do
    setup :create_steps_dataclips

    setup %{conn: conn, user: user} do
      %{conn: log_in_user(conn, user)}
    end

    test "scrubbs lines from step_result dataclip", %{
      conn: conn,
      step2: selected_step
    } do
      conn = get(conn, ~p"/dataclip/body/#{selected_step.output_dataclip_id}")

      body = response(conn, 200)

      dataclip_lines = String.split(body, "\n")

      # foo: "bar" is not scrubbed because it is from a following job executed on step3
      expected_lines = [
        ~S("integer":***),
        ~S("another_no":***),
        ~S("third_no":12***34),
        ~S("map":{"list":[{"any-key":"some-***s"}]}),
        ~S("bool":true),
        ~S("foo":"bar")
      ]

      Enum.each(dataclip_lines, fn line ->
        Enum.any?(expected_lines, fn expected_line ->
          String.contains?(line, expected_line)
        end)
      end)
    end

    test "returns 304 when the dataclip is not outdated", %{
      conn: conn,
      output_dataclip: dataclip
    } do
      last_modified =
        Timex.format!(
          dataclip.updated_at,
          "%a, %d %b %Y %H:%M:%S GMT",
          :strftime
        )

      conn =
        conn
        |> put_req_header("if-modified-since", last_modified)
        |> get(~p"/dataclip/body/#{dataclip.id}")

      assert conn.status == 304
    end

    test "returns 200 when the dataclip is outdated", %{
      conn: conn,
      output_dataclip: dataclip
    } do
      last_modified =
        dataclip.updated_at
        |> DateTime.add(-20)
        |> Timex.format!(
          "%a, %d %b %Y %H:%M:%S GMT",
          :strftime
        )

      conn =
        conn
        |> put_req_header("if-modified-since", last_modified)
        |> get(~p"/dataclip/body/#{dataclip.id}")

      assert response(conn, 200) =~ "some-bars"
      assert get_resp_header(conn, "cache-control") == ["private, max-age=86400"]
      assert get_resp_header(conn, "vary") == ["Accept-Encoding, Cookie"]

      assert get_resp_header(conn, "last-modified") == [
               Timex.format!(
                 dataclip.updated_at,
                 "%a, %d %b %Y %H:%M:%S GMT",
                 :strftime
               )
             ]
    end

    test "handles invalid If-Modified-Since header gracefully", %{
      conn: conn,
      output_dataclip: dataclip
    } do
      conn =
        conn
        |> put_req_header("if-modified-since", "invalid-date-format")
        |> get(~p"/dataclip/body/#{dataclip.id}")

      assert response(conn, 200) =~ "some-bars"
    end

    test "returns 403 when the user is not part of the dataclip's project", %{
      conn: conn,
      output_dataclip: dataclip
    } do
      user = insert(:user)
      conn = conn |> log_in_user(user) |> get(~p"/dataclip/body/#{dataclip.id}")

      assert conn.status == 403
    end
  end

  describe "GET /projects/:project_id/jobs/:job_id/dataclips" do
    setup do
      user = insert(:user)
      project = insert(:project, project_users: [%{user: user}])
      workflow = insert(:workflow, project: project)
      job = insert(:job, workflow: workflow)
      dataclip = insert(:dataclip, project: project, type: :http_request)

      %{
        user: user,
        project: project,
        job: job,
        dataclip: dataclip,
        conn: build_conn() |> log_in_user(user)
      }
    end

    test "returns dataclips for job with default filters", %{
      conn: conn,
      project: project,
      job: job
    } do
      conn = get(conn, ~p"/projects/#{project}/jobs/#{job}/dataclips")

      assert %{
               "data" => dataclips,
               "next_cron_run_dataclip_id" => _,
               "can_edit_dataclip" => can_edit
             } = json_response(conn, 200)

      assert is_list(dataclips)
      assert is_boolean(can_edit)
    end

    test "returns dataclips with query parameter", %{
      conn: conn,
      project: project,
      job: job
    } do
      conn =
        get(conn, ~p"/projects/#{project}/jobs/#{job}/dataclips?query=test")

      assert %{"data" => _dataclips} = json_response(conn, 200)
    end

    test "returns dataclips with type filter", %{
      conn: conn,
      project: project,
      job: job
    } do
      conn =
        get(
          conn,
          ~p"/projects/#{project}/jobs/#{job}/dataclips?type=http_request"
        )

      assert %{"data" => _dataclips} = json_response(conn, 200)
    end

    test "requires authentication", %{project: project, job: job} do
      conn = build_conn()
      conn = get(conn, ~p"/projects/#{project}/jobs/#{job}/dataclips")

      assert redirected_to(conn) == ~p"/users/log_in"
    end

    test "requires project access", %{conn: conn, job: job} do
      other_user = insert(:user)
      other_project = insert(:project, project_users: [%{user: other_user}])

      conn = get(conn, ~p"/projects/#{other_project}/jobs/#{job}/dataclips")

      # Returns 401 because Projects.get_project! raises for unauthorized access
      assert html_response(conn, 401) =~ "Authorization Error"
    end
  end

  describe "GET /projects/:project_id/runs/:run_id/dataclip" do
    setup do
      user = insert(:user)
      project = insert(:project, project_users: [%{user: user}])
      workflow = insert(:workflow, project: project)
      job = insert(:job, workflow: workflow)
      trigger = insert(:trigger, workflow: workflow)
      dataclip = insert(:dataclip, project: project)

      work_order =
        insert(:workorder,
          workflow: workflow,
          trigger: trigger,
          dataclip: dataclip
        )

      run =
        insert(:run,
          work_order: work_order,
          dataclip: dataclip,
          starting_trigger: trigger
        )

      step = insert(:step, job: job, input_dataclip: dataclip)
      insert(:run_step, run: run, step: step)

      %{
        user: user,
        project: project,
        run: run,
        job: job,
        dataclip: dataclip,
        conn: build_conn() |> log_in_user(user)
      }
    end

    test "returns dataclip for run and job", %{
      conn: conn,
      project: project,
      run: run,
      job: job
    } do
      conn =
        get(
          conn,
          ~p"/projects/#{project}/runs/#{run}/dataclip?job_id=#{job.id}"
        )

      assert %{
               "dataclip" => _dataclip,
               "run_step" => _run_step
             } = json_response(conn, 200)
    end

    test "requires authentication", %{project: project, run: run, job: job} do
      conn = build_conn()

      conn =
        get(
          conn,
          ~p"/projects/#{project}/runs/#{run}/dataclip?job_id=#{job.id}"
        )

      assert redirected_to(conn) == ~p"/users/log_in"
    end

    test "requires project access", %{
      conn: conn,
      run: run,
      job: job
    } do
      other_user = insert(:user)
      other_project = insert(:project, project_users: [%{user: other_user}])

      conn =
        get(
          conn,
          ~p"/projects/#{other_project}/runs/#{run}/dataclip?job_id=#{job.id}"
        )

      # Returns 401 because Projects.get_project! raises for unauthorized access
      assert html_response(conn, 401) =~ "Authorization Error"
    end
  end

  describe "PATCH /projects/:project_id/dataclips/:dataclip_id" do
    setup do
      user = insert(:user)
      project = insert(:project, project_users: [%{user: user}])
      dataclip = insert(:dataclip, project: project)

      %{
        user: user,
        project: project,
        dataclip: dataclip,
        conn: build_conn() |> log_in_user(user)
      }
    end

    test "updates dataclip name", %{
      conn: conn,
      project: project,
      dataclip: dataclip
    } do
      conn =
        patch(conn, ~p"/projects/#{project}/dataclips/#{dataclip}", %{
          name: "My Custom Input"
        })

      assert %{"data" => updated} = json_response(conn, 200)
      assert updated["name"] == "My Custom Input"
    end

    test "allows removing name by setting to null", %{
      conn: conn,
      project: project
    } do
      dataclip = insert(:dataclip, project: project, name: "Named Dataclip")

      conn =
        patch(conn, ~p"/projects/#{project}/dataclips/#{dataclip}", %{
          name: nil
        })

      assert %{"data" => updated} = json_response(conn, 200)
      assert is_nil(updated["name"])
    end

    test "requires authentication", %{project: project, dataclip: dataclip} do
      conn = build_conn()

      conn =
        patch(conn, ~p"/projects/#{project}/dataclips/#{dataclip}", %{
          name: "New Name"
        })

      assert redirected_to(conn) == ~p"/users/log_in"
    end

    test "requires edit_workflow permission", %{
      conn: _conn
    } do
      # Create a project where user is a viewer (no edit permission)
      viewer_user = insert(:user)
      other_project = insert(:project)

      insert(:project_user,
        project: other_project,
        user: viewer_user,
        role: :viewer
      )

      other_dataclip = insert(:dataclip, project: other_project)

      conn =
        build_conn()
        |> log_in_user(viewer_user)
        |> patch(
          ~p"/projects/#{other_project}/dataclips/#{other_dataclip}",
          %{
            name: "New Name"
          }
        )

      # Returns 401 because viewer role doesn't have edit_workflow permission
      assert html_response(conn, 401) =~ "Authorization Error"
    end

    test "requires access to dataclip's project", %{
      conn: conn
    } do
      other_user = insert(:user)
      other_project = insert(:project, project_users: [%{user: other_user}])
      other_dataclip = insert(:dataclip, project: other_project)

      conn =
        patch(
          conn,
          ~p"/projects/#{other_project}/dataclips/#{other_dataclip}",
          %{
            name: "New Name"
          }
        )

      # Returns 401 because Projects.get_project! raises for unauthorized access
      assert html_response(conn, 401) =~ "Authorization Error"
    end
  end
end
