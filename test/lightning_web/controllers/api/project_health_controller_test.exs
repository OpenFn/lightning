defmodule LightningWeb.API.ProjectHealthControllerTest do
  use LightningWeb.ConnCase, async: true

  import Lightning.Factories

  setup %{conn: conn} do
    user = insert(:user)
    project = insert(:project, project_users: [%{user: user, role: :owner}])

    conn = conn |> put_req_header("accept", "application/json")

    %{conn: conn, user: user, project: project}
  end

  defp get_outcomes(conn, user, project_id) do
    conn
    |> log_in_user(user)
    |> get(~p"/api/projects/#{project_id}/health/outcomes")
  end

  describe "GET /health/outcomes" do
    test "a project member is served 200 and real counts", %{
      conn: conn,
      user: user,
      project: project
    } do
      workflow = insert(:simple_workflow, project: project)

      insert(:workorder,
        workflow: workflow,
        trigger: hd(workflow.triggers),
        dataclip: insert(:dataclip),
        state: :success
      )

      outcomes =
        conn |> get_outcomes(user, project.id) |> json_response(200)

      assert %{"from" => from, "to" => to} = outcomes["window"]
      assert {:ok, from, _} = DateTime.from_iso8601(from)
      assert {:ok, to, _} = DateTime.from_iso8601(to)
      assert DateTime.diff(to, from, :day) == 30

      assert %{"success" => 1} = outcomes["counts"]
    end

    test "an anonymous request is refused", %{conn: conn, project: project} do
      conn = get(conn, ~p"/api/projects/#{project.id}/health/outcomes")

      assert conn.status == 401
    end

    test "a non-member gets 404", %{conn: conn, project: project} do
      assert %{status: 404} = get_outcomes(conn, insert(:user), project.id)
    end

    test "a member cannot read a project scheduled for deletion", %{
      conn: conn,
      user: user,
      project: project
    } do
      project
      |> Ecto.Changeset.change(scheduled_deletion: ~U[2026-01-01 00:00:00Z])
      |> Lightning.Repo.update!()

      assert %{status: 404} = get_outcomes(conn, user, project.id)
    end

    test "a malformed project id gets 404", %{conn: conn, user: user} do
      assert %{status: 404} = get_outcomes(conn, user, "not-a-uuid")
    end

    test "an unknown project id gets 404", %{conn: conn, user: user} do
      assert %{status: 404} =
               get_outcomes(conn, user, Ecto.UUID.generate())
    end

    test "an MFA-required project refuses a user who hasn't satisfied MFA", %{
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

      assert %{status: 404} = get_outcomes(conn, unenrolled, project.id)

      # Not unreadable in general: an enrolled member is still served.
      assert %{status: 200} = get_outcomes(conn, enrolled, project.id)
    end
  end
end
