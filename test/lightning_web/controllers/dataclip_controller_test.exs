defmodule LightningWeb.DataclipControllerTest do
  use LightningWeb.ConnCase, async: true
  import Lightning.Factories

  defp create_steps_dataclips(_context) do
    user = insert(:user)
    project = insert(:project, project_users: [%{user: user}])

    credential1 =
      insert(:credential, name: "My Credential1", user: user)
      |> with_body(%{body: %{"secret" => "55", "another_secret" => "bar"}})

    credential2 =
      insert(:credential, name: "My Credential2", user: user)
      |> with_body(%{
        body: %{"pin" => 123_456, "looks_like_a_number" => "789"}
      })

    credential3 =
      insert(:credential, name: "My Credential3", user: user)
      |> with_body(%{body: %{"foo" => "bar"}})

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
        steps: [step1, step2, step3]
      )

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

    test "scrubs http_request dataclip with webhook auth credentials", %{
      conn: conn,
      user: user
    } do
      project = insert(:project, project_users: [%{user: user}])
      workflow = insert(:workflow, project: project)
      trigger = insert(:trigger, workflow: workflow, type: :webhook)

      webhook_auth =
        insert(:webhook_auth_method,
          project: project,
          auth_type: :basic,
          username: "webhook_user",
          password: "webhook_secret_pass"
        )

      trigger
      |> Lightning.Repo.preload(:webhook_auth_methods)
      |> Ecto.Changeset.change()
      |> Ecto.Changeset.put_assoc(:webhook_auth_methods, [webhook_auth])
      |> Lightning.Repo.update!()

      dataclip =
        insert(:dataclip,
          project: project,
          type: :http_request,
          body: %{
            "headers" => %{
              "authorization" =>
                "Basic #{Base.encode64("webhook_user:webhook_secret_pass")}"
            },
            "data" => "test payload"
          }
        )

      insert(:workorder,
        workflow: workflow,
        trigger: trigger,
        dataclip: dataclip
      )

      conn = get(conn, ~p"/dataclip/body/#{dataclip.id}")
      body = response(conn, 200)

      # The password and base64-encoded basic auth should be scrubbed
      refute body =~ "webhook_secret_pass"
      refute body =~ Base.encode64("webhook_user:webhook_secret_pass")
      # The scrubbed placeholder should be present
      assert body =~ "***"
      # Non-sensitive data should still be present
      assert body =~ "test payload"
    end

    test "scrubs lines from step_result dataclip", %{
      conn: conn,
      step2: selected_step
    } do
      conn = get(conn, ~p"/dataclip/body/#{selected_step.output_dataclip_id}")

      body = response(conn, 200)

      assert body =~ ~S("integer": ***)
      assert body =~ ~S("another_no": ***)
      assert body =~ ~S("third_no": 12***34)
      assert body =~ ~S("any-key": "some-***s")
      assert body =~ ~S("bool": true)
      assert body =~ ~S("foo": "***")
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

      assert response(conn, 200) =~ ~S("any-key")
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

      assert response(conn, 200) =~ ~S("any-key")
    end

    test "returns 403 when the user is not part of the dataclip's project", %{
      conn: conn,
      output_dataclip: dataclip
    } do
      user = insert(:user)
      conn = conn |> log_in_user(user) |> get(~p"/dataclip/body/#{dataclip.id}")

      assert conn.status == 403
    end

    test "returns 404 when the dataclip does not exist", %{conn: conn} do
      assert_error_sent(404, fn ->
        get(conn, ~p"/dataclip/body/#{Ecto.UUID.generate()}")
      end)
    end

    test "returns 200 with \"null\" body when the dataclip body is nil", %{
      conn: conn,
      user: user
    } do
      project = insert(:project, project_users: [%{user: user}])
      dataclip = insert(:dataclip, project: project, type: :global, body: nil)

      conn = get(conn, ~p"/dataclip/body/#{dataclip.id}")

      assert response(conn, 200) == "null"
    end

    test "does not scrub :global dataclip bodies", %{conn: conn, user: user} do
      project = insert(:project, project_users: [%{user: user}])

      dataclip =
        insert(:dataclip,
          project: project,
          type: :global,
          body: %{"secret_looking_thing" => "hunter2"}
        )

      conn = get(conn, ~p"/dataclip/body/#{dataclip.id}")
      body = response(conn, 200)

      assert body =~ "hunter2"
      refute body =~ "***"
    end

    test "redirects to login when user is not authenticated", %{
      output_dataclip: dataclip
    } do
      conn = build_conn() |> get(~p"/dataclip/body/#{dataclip.id}")

      assert redirected_to(conn) == ~p"/users/log_in"
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

    # NOTE: This test currently fails with an unhandled `ArgumentError` because
    # `String.to_integer/1` in `DataclipController.search/2` is unguarded
    # (lib/lightning_web/controllers/dataclip_controller.ex:136). Once the
    # controller validates the `limit` param, it should return 400 instead of
    # crashing.
    test "returns 400 when limit is not a positive integer", %{
      conn: conn,
      project: project,
      job: job
    } do
      for bad_limit <- ["abc", "", "10.5"] do
        conn =
          get(
            conn,
            ~p"/projects/#{project}/jobs/#{job}/dataclips?limit=#{bad_limit}"
          )

        assert response(conn, 400)
      end
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

    test "returns 404 when the dataclip belongs to a different project than the URL project_id" do
      user = insert(:user)

      # Project A: user has :edit_workflow (admin role).
      project_a =
        insert(:project, project_users: [%{user: user, role: :admin}])

      # Project B: user is a member (so :view_dataclip passes via membership),
      # and the dataclip lives here.
      project_b =
        insert(:project, project_users: [%{user: user, role: :admin}])

      dataclip_in_b = insert(:dataclip, project: project_b)

      conn =
        build_conn()
        |> log_in_user(user)
        |> patch(
          ~p"/projects/#{project_a}/dataclips/#{dataclip_in_b}",
          %{name: "Sneaky Rename"}
        )

      # Post-fix: the controller should refuse to update a dataclip via a
      # mismatched project URL. Currently this returns 200 with the updated
      # dataclip — that's the bug under test.
      assert conn.status == 404
    end
  end
end
