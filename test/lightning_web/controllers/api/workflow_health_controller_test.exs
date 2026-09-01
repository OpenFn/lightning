defmodule LightningWeb.API.WorkflowHealthControllerTest do
  use LightningWeb.ConnCase, async: true

  import Lightning.Factories

  setup %{conn: conn} do
    user = insert(:user)
    project = insert(:project, project_users: [%{user: user, role: :owner}])
    workflow = insert(:simple_workflow, project: project)

    conn = conn |> put_req_header("accept", "application/json")

    %{conn: conn, user: user, project: project, workflow: workflow}
  end

  defp get_outcomes(conn, user, project_id, workflow_id) do
    conn
    |> log_in_user(user)
    |> get(
      ~p"/api/projects/#{project_id}/workflows/#{workflow_id}/health/outcomes"
    )
  end

  defp get_failures(conn, user, project_id, workflow_id) do
    conn
    |> log_in_user(user)
    |> get(
      ~p"/api/projects/#{project_id}/workflows/#{workflow_id}/health/failures"
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

    test "a malformed id is refused rather than crashing the request", %{
      conn: conn,
      user: user,
      project: project,
      workflow: workflow
    } do
      assert %{status: 404} = get_outcomes(conn, user, "not-a-uuid", workflow.id)

      assert %{status: 404} = get_outcomes(conn, user, project.id, "not-a-uuid")
    end

    # Both actions share one plug, so this only has to prove the plug runs on
    # the second one too.
    test "the failures slice is guarded by the same check", %{
      conn: conn,
      project: project,
      workflow: workflow
    } do
      assert %{status: 404} =
               get_failures(conn, insert(:user), project.id, workflow.id)
    end
  end

  describe "GET /health/outcomes" do
    test "counts runs from the last 30 days, grouped by state", %{
      conn: conn,
      user: user,
      project: project,
      workflow: workflow
    } do
      %{triggers: [trigger]} = workflow

      work_order =
        insert(:workorder,
          workflow: workflow,
          trigger: trigger,
          dataclip: insert(:dataclip),
          state: :failed
        )

      run = fn attrs ->
        insert(
          :run,
          Keyword.merge(
            [
              work_order: work_order,
              starting_trigger: trigger,
              dataclip: insert(:dataclip)
            ],
            attrs
          )
        )
      end

      for state <- [:success, :success, :crashed, :started] do
        run.(state: state)
      end

      # Outside the window — must not be counted.
      run.(state: :success, inserted_at: Timex.shift(Timex.now(), days: -31))

      outcomes =
        conn |> get_outcomes(user, project.id, workflow.id) |> json_response(200)

      assert %{"from" => from, "to" => to} = outcomes["window"]
      assert {:ok, from, _} = DateTime.from_iso8601(from)
      assert {:ok, to, _} = DateTime.from_iso8601(to)
      assert DateTime.diff(to, from, :day) == 30

      assert %{"success" => 2, "crashed" => 1, "failed" => 0} =
               outcomes["counts"]
    end

    test "reports zeroes for a workflow with no runs", %{
      conn: conn,
      user: user,
      project: project,
      workflow: workflow
    } do
      outcomes =
        conn |> get_outcomes(user, project.id, workflow.id) |> json_response(200)

      assert outcomes["counts"] ==
               Map.new(Lightning.Run.final_states(), &{to_string(&1), 0})
    end
  end

  describe "GET /health/failures" do
    test "returns the signature parts and run count for each failure", %{
      conn: conn,
      user: user,
      project: project,
      workflow: workflow
    } do
      %{triggers: [trigger], jobs: [job | _]} = workflow

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
      assert DateTime.diff(to, from, :day) == 30

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
end
