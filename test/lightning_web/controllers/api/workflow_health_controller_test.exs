defmodule LightningWeb.API.WorkflowHealthControllerTest do
  use LightningWeb.ConnCase, async: true

  import Lightning.Factories

  alias Lightning.Workflows.Snapshot

  setup %{conn: conn} do
    user = insert(:user)
    project = insert(:project, project_users: [%{user: user, role: :owner}])
    workflow = insert(:simple_workflow, project: project)

    conn = conn |> put_req_header("accept", "application/json")

    %{conn: conn, user: user, project: project, workflow: workflow}
  end

  defp get_outcomes(conn, user, project_id, workflow_id, params \\ %{}) do
    conn
    |> log_in_user(user)
    |> get(
      ~p"/api/projects/#{project_id}/workflows/#{workflow_id}/health/outcomes",
      params
    )
  end

  defp get_failures(conn, user, project_id, workflow_id, params \\ %{}) do
    conn
    |> log_in_user(user)
    |> get(
      ~p"/api/projects/#{project_id}/workflows/#{workflow_id}/health/failures",
      params
    )
  end

  defp get_runs(
         conn,
         user,
         project_id,
         workflow_id,
         params \\ %{},
         headers \\ []
       ) do
    Enum.reduce(headers, log_in_user(conn, user), fn {name, value}, conn ->
      put_req_header(conn, name, value)
    end)
    |> get(
      ~p"/api/projects/#{project_id}/workflows/#{workflow_id}/health/runs",
      params
    )
  end

  describe "authorization" do
    test "a project member is served", %{
      conn: conn,
      user: user,
      project: project,
      workflow: workflow
    } do
      assert %{status: 200} = get_outcomes(conn, user, project.id, workflow.id)
    end

    test "an anonymous request is refused", %{
      conn: conn,
      project: project,
      workflow: workflow
    } do
      conn =
        get(
          conn,
          ~p"/api/projects/#{project.id}/workflows/#{workflow.id}/health/outcomes"
        )

      assert conn.status == 401
    end

    test "a non-member is refused", %{
      conn: conn,
      project: project,
      workflow: workflow
    } do
      assert %{status: 404} =
               get_outcomes(conn, insert(:user), project.id, workflow.id)
    end

    # :validate_days runs after :authorize_workflow, so a bad `days` value
    # never gets the chance to produce a 400 for someone who can't see the
    # workflow in the first place.
    test "a non-member is refused with 404, not 400, even with an invalid days value",
         %{
           conn: conn,
           project: project,
           workflow: workflow
         } do
      assert %{status: 404} =
               get_outcomes(conn, insert(:user), project.id, workflow.id, %{
                 "days" => "banana"
               })
    end

    test "a member of another project cannot read this workflow", %{
      conn: conn,
      user: user,
      project: project
    } do
      other_workflow = insert(:simple_workflow)

      assert %{status: 404} =
               get_outcomes(conn, user, project.id, other_workflow.id)

      # Nor by naming the other workflow's own project, which they aren't in.
      assert %{status: 404} =
               get_outcomes(
                 conn,
                 user,
                 other_workflow.project_id,
                 other_workflow.id
               )
    end

    # Support users have no `project_users` row, so a membership check alone
    # would refuse them where the rest of the app admits them.
    test "a support user is served a project that allows support access", %{
      conn: conn,
      workflow: workflow
    } do
      support_user = insert(:user, support_user: true)
      opted_in = insert(:project, allow_support_access: true)
      opted_in_workflow = insert(:simple_workflow, project: opted_in)

      assert %{status: 200} =
               get_outcomes(
                 conn,
                 support_user,
                 opted_in.id,
                 opted_in_workflow.id
               )

      # Not a blanket pass: a project that hasn't opted in still refuses them.
      assert %{status: 404} =
               get_outcomes(
                 conn,
                 support_user,
                 workflow.project_id,
                 workflow.id
               )
    end

    test "a member cannot read a project scheduled for deletion", %{
      conn: conn,
      user: user,
      project: project,
      workflow: workflow
    } do
      project
      |> Ecto.Changeset.change(scheduled_deletion: ~U[2026-01-01 00:00:00Z])
      |> Lightning.Repo.update!()

      assert %{status: 404} = get_outcomes(conn, user, project.id, workflow.id)
    end

    # The LiveView redirects this person to `/mfa_required`; a JSON client has
    # nothing to do with that, and 404 doesn't confirm the project exists.
    test "a member who has not enrolled is refused a project requiring MFA", %{
      conn: conn
    } do
      unenrolled = insert(:user, mfa_enabled: false)
      enrolled = insert(:user, mfa_enabled: true)

      project =
        insert(:project,
          requires_mfa: true,
          project_users: [
            %{user: unenrolled, role: :owner},
            %{user: enrolled, role: :viewer}
          ]
        )

      workflow = insert(:simple_workflow, project: project)

      assert %{status: 404} =
               get_outcomes(conn, unenrolled, project.id, workflow.id)

      # Not unreadable in general: an enrolled member is still served.
      assert %{status: 200} =
               get_outcomes(conn, enrolled, project.id, workflow.id)
    end

    # The LiveView refuses this through `Query.workflows_for/1`; the API reads
    # the same query now, so it refuses it too.
    test "a member cannot read a workflow marked for deletion", %{
      conn: conn,
      user: user,
      project: project,
      workflow: workflow
    } do
      workflow
      |> Ecto.Changeset.change(deleted_at: ~U[2026-01-01 00:00:00Z])
      |> Lightning.Repo.update!()

      assert %{status: 404} = get_outcomes(conn, user, project.id, workflow.id)
      assert %{status: 404} = get_failures(conn, user, project.id, workflow.id)
    end

    test "a malformed id is refused rather than crashing the request", %{
      conn: conn,
      user: user,
      project: project,
      workflow: workflow
    } do
      assert %{status: 404} = get_outcomes(conn, user, "not-a-uuid", workflow.id)

      assert %{status: 404} = get_outcomes(conn, user, project.id, "not-a-uuid")
    end

    # Every action shares one plug, so this only has to prove the plug runs on
    # the others too.
    test "the other slices are guarded by the same check", %{
      conn: conn,
      project: project,
      workflow: workflow
    } do
      stranger = insert(:user)

      assert %{status: 404} =
               get_failures(conn, stranger, project.id, workflow.id)

      assert %{status: 404} = get_runs(conn, stranger, project.id, workflow.id)
    end
  end

  describe "GET /health/outcomes" do
    test "counts work orders from the last 7 days, grouped by state", %{
      conn: conn,
      user: user,
      project: project,
      workflow: workflow
    } do
      %{triggers: [trigger]} = workflow

      work_order = fn attrs ->
        insert(
          :workorder,
          Keyword.merge(
            [
              workflow: workflow,
              trigger: trigger,
              dataclip: insert(:dataclip)
            ],
            attrs
          )
        )
      end

      # `:running` has no outcome yet, so it is not counted at all.
      for state <- [:success, :success, :crashed, :running] do
        work_order.(state: state)
      end

      # Outside the window — must not be counted.
      work_order.(
        state: :success,
        last_activity: Timex.shift(Timex.now(), days: -8)
      )

      outcomes =
        conn |> get_outcomes(user, project.id, workflow.id) |> json_response(200)

      assert %{"from" => from, "to" => to} = outcomes["window"]
      assert {:ok, from, _} = DateTime.from_iso8601(from)
      assert {:ok, to, _} = DateTime.from_iso8601(to)
      assert DateTime.diff(to, from, :day) == 7

      assert %{"success" => 2, "crashed" => 1, "failed" => 0} =
               outcomes["counts"]
    end

    test "reports zeroes for a workflow with no work orders", %{
      conn: conn,
      user: user,
      project: project,
      workflow: workflow
    } do
      outcomes =
        conn |> get_outcomes(user, project.id, workflow.id) |> json_response(200)

      assert outcomes["counts"] ==
               Map.new(Lightning.WorkOrder.final_states(), &{to_string(&1), 0})
    end
  end

  describe "GET /health/failures" do
    test "returns the signature parts and work order count for each failure", %{
      conn: conn,
      user: user,
      project: project,
      workflow: workflow
    } do
      %{triggers: [trigger], jobs: [job | _]} = workflow

      # The signature names the job as its snapshot recorded it, so the step has
      # to run against the workflow's own snapshot, not the unrelated one
      # `step_factory` builds.
      {:ok, snapshot} = Snapshot.create(workflow)

      work_order =
        insert(:workorder,
          workflow: workflow,
          trigger: trigger,
          dataclip: insert(:dataclip),
          state: :failed
        )

      insert(:run,
        work_order: work_order,
        starting_trigger: trigger,
        dataclip: insert(:dataclip),
        state: :failed,
        steps: [
          build(:step,
            job: job,
            snapshot: snapshot,
            input_dataclip: build(:dataclip),
            exit_reason: "fail",
            error_type: "RuntimeError"
          )
        ]
      )

      body =
        conn
        |> get_failures(user, project.id, workflow.id)
        |> json_response(200)

      assert %{"from" => from, "to" => to} = body["window"]
      assert {:ok, from, _} = DateTime.from_iso8601(from)
      assert {:ok, to, _} = DateTime.from_iso8601(to)
      assert DateTime.diff(to, from, :day) == 7

      assert [
               %{
                 "count" => 1,
                 "exit_reason" => "fail",
                 "error_type" => "RuntimeError",
                 "step_name" => step_name,
                 "adaptor" => adaptor
               }
             ] = body["signatures"]

      assert step_name == job.name
      assert adaptor == job.adaptor
    end

    test "returns an empty list for a workflow with no failures", %{
      conn: conn,
      user: user,
      project: project,
      workflow: workflow
    } do
      body =
        conn
        |> get_failures(user, project.id, workflow.id)
        |> json_response(200)

      assert body["signatures"] == []
    end
  end

  describe "GET /health/runs" do
    test "returns every bucket in the window, counted by state", %{
      conn: conn,
      user: user,
      project: project,
      workflow: workflow
    } do
      trigger = hd(workflow.triggers)
      at = DateTime.add(DateTime.utc_now(), -90, :minute)

      work_order =
        insert(:workorder,
          workflow: workflow,
          trigger: trigger,
          dataclip: insert(:dataclip),
          state: :failed,
          last_activity: at
        )

      insert(:run,
        work_order: work_order,
        starting_trigger: trigger,
        dataclip: insert(:dataclip),
        state: :failed,
        inserted_at: at
      )

      response =
        conn
        |> get_runs(user, project.id, workflow.id, %{"days" => "1"})
        |> json_response(200)

      assert Enum.sum_by(response["buckets"], & &1["failed"]) == 1
      assert Enum.sum_by(response["buckets"], & &1["success"]) == 0
    end
  end

  # Nothing in Lightning records a reader's timezone, so the browser says. No
  # header, or one saying the browser does not know, is UTC; anything else the
  # tz database does not know is a 400, because the browser chose it.
  describe "x-timezone" do
    test "cuts the grid on the timezone the reader sent", %{
      conn: conn,
      user: user,
      project: project,
      workflow: workflow
    } do
      response =
        conn
        |> get_runs(user, project.id, workflow.id, %{"days" => "1"}, [
          {"x-timezone", "Africa/Nairobi"}
        ])
        |> json_response(200)

      assert response["timezone"] == "Africa/Nairobi"

      {:ok, from, 0} = DateTime.from_iso8601(response["window"]["from"])
      local = DateTime.shift_zone!(from, "Africa/Nairobi")

      assert local.minute == 0 and local.second == 0
    end

    test "falls back to UTC without the header", %{
      conn: conn,
      user: user,
      project: project,
      workflow: workflow
    } do
      response =
        conn
        |> get_runs(user, project.id, workflow.id, %{"days" => "1"})
        |> json_response(200)

      assert response["timezone"] == "Etc/UTC"
    end

    # A host clock CLDR could not map to a zone. The browser is saying it does
    # not know, not naming one we failed to recognise.
    test "falls back to UTC when the browser says it does not know", %{
      conn: conn,
      user: user,
      project: project,
      workflow: workflow
    } do
      response =
        conn
        |> get_runs(user, project.id, workflow.id, %{"days" => "1"}, [
          {"x-timezone", "Etc/Unknown"}
        ])
        |> json_response(200)

      assert response["timezone"] == "Etc/UTC"
    end

    test "tells caches the body turns on the header", %{
      conn: conn,
      user: user,
      project: project,
      workflow: workflow
    } do
      conn = get_runs(conn, user, project.id, workflow.id, %{"days" => "1"})

      assert get_resp_header(conn, "vary") == ["x-timezone"]
    end

    # Unknown, empty, and long — the cache key has to stay bounded to the tz
    # database whatever arrives.
    test "rejects a value it cannot use", %{
      conn: conn,
      user: user,
      project: project,
      workflow: workflow
    } do
      for value <- ["Mars/Olympus", "", String.duplicate("x", 5_000)] do
        response =
          conn
          |> get_runs(user, project.id, workflow.id, %{"days" => "1"}, [
            {"x-timezone", value}
          ])
          |> json_response(400)

        assert response == %{
                 "error" => "x-timezone must be an IANA timezone name"
               }
      end
    end
  end

  describe "?days=" do
    @accepted_days [1, 7, 30]

    test "each accepted value returns a window that many days wide", %{
      conn: conn,
      user: user,
      project: project,
      workflow: workflow
    } do
      for days <- @accepted_days do
        outcomes =
          conn
          |> get_outcomes(user, project.id, workflow.id, %{
            "days" => Integer.to_string(days)
          })
          |> json_response(200)

        assert %{"from" => from, "to" => to} = outcomes["window"]
        assert {:ok, from, _} = DateTime.from_iso8601(from)
        assert {:ok, to, _} = DateTime.from_iso8601(to)
        assert DateTime.diff(to, from, :day) == days

        failures =
          conn
          |> get_failures(user, project.id, workflow.id, %{
            "days" => Integer.to_string(days)
          })
          |> json_response(200)

        assert %{"from" => from, "to" => to} = failures["window"]
        assert {:ok, from, _} = DateTime.from_iso8601(from)
        assert {:ok, to, _} = DateTime.from_iso8601(to)
        assert DateTime.diff(to, from, :day) == days
      end
    end

    test "an unaccepted value is refused", %{
      conn: conn,
      user: user,
      project: project,
      workflow: workflow
    } do
      for bad_days <- ["banana", "36500", "0", "7.5", "007"] do
        assert %{status: 400} =
                 get_outcomes(conn, user, project.id, workflow.id, %{
                   "days" => bad_days
                 })

        assert %{status: 400} =
                 get_failures(conn, user, project.id, workflow.id, %{
                   "days" => bad_days
                 })
      end
    end
  end
end
