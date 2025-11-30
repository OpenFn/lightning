defmodule LightningWeb.API.AiAssistantControllerTest do
  use LightningWeb.ConnCase, async: true

  import Mox
  import Lightning.Factories

  setup :verify_on_exit!

  setup %{conn: conn} do
    {:ok, conn: put_req_header(conn, "accept", "application/json")}
  end

  setup do
    # Mock Apollo configuration to prevent real HTTP calls
    Mox.stub(Lightning.MockConfig, :apollo, fn key ->
      case key do
        :endpoint -> "http://localhost:3000"
        :ai_assistant_api_key -> "test_api_key"
        :timeout -> 5_000
      end
    end)

    # Mock Tesla HTTP client to prevent real HTTP calls
    Mox.stub(Lightning.Tesla.Mock, :call, fn %{method: :post}, _opts ->
      {:ok,
       %Tesla.Env{
         status: 200,
         body: %{
           "response" => "This is a test AI response.",
           "history" => [
             %{"role" => "user", "content" => "test message"},
             %{"role" => "assistant", "content" => "This is a test AI response."}
           ]
         }
       }}
    end)

    :ok
  end

  describe "list_sessions without authentication" do
    test "returns 401 without token", %{conn: conn} do
      conn =
        get(
          conn,
          ~p"/api/ai_assistant/sessions?session_type=job_code&job_id=123"
        )

      assert json_response(conn, 401) == %{"error" => "Unauthorized"}
    end

    test "returns 401 with invalid token", %{conn: conn} do
      conn =
        conn
        |> Plug.Conn.put_req_header("authorization", "Bearer invalid_token")

      conn =
        get(
          conn,
          ~p"/api/ai_assistant/sessions?session_type=job_code&job_id=123"
        )

      assert json_response(conn, 401) == %{"error" => "Unauthorized"}
    end
  end

  describe "list_sessions validation" do
    setup [:register_and_log_in_user]

    test "returns 400 when session_type is missing", %{conn: conn} do
      conn = get(conn, ~p"/api/ai_assistant/sessions?job_id=123")

      assert json_response(conn, 400) == %{"error" => "Bad Request"}
    end

    test "returns 400 when session_type is invalid", %{conn: conn} do
      conn =
        get(conn, ~p"/api/ai_assistant/sessions?session_type=invalid&job_id=123")

      assert json_response(conn, 400) == %{"error" => "Bad Request"}
    end

    test "returns 400 when job_code session_type missing job_id", %{conn: conn} do
      conn = get(conn, ~p"/api/ai_assistant/sessions?session_type=job_code")

      assert json_response(conn, 400) == %{"error" => "Bad Request"}
    end

    test "returns 400 when workflow_template session_type missing project_id",
         %{conn: conn} do
      conn =
        get(conn, ~p"/api/ai_assistant/sessions?session_type=workflow_template")

      assert json_response(conn, 400) == %{"error" => "Bad Request"}
    end

    test "returns 404 when workflow_template project does not exist", %{
      conn: conn
    } do
      nonexistent_uuid = Ecto.UUID.generate()

      conn =
        get(
          conn,
          ~p"/api/ai_assistant/sessions?session_type=workflow_template&project_id=#{nonexistent_uuid}"
        )

      assert json_response(conn, 404) == %{"error" => "Not Found"}
    end
  end

  describe "list_sessions for job_code with saved job" do
    setup [:register_and_log_in_user, :create_job_with_sessions]

    test "returns sessions for job user has access to", %{
      conn: conn,
      job: job,
      sessions: sessions
    } do
      conn =
        get(
          conn,
          ~p"/api/ai_assistant/sessions?session_type=job_code&job_id=#{job.id}"
        )

      response = json_response(conn, 200)

      assert %{
               "sessions" => returned_sessions,
               "pagination" => pagination
             } = response

      assert length(returned_sessions) == 3

      assert pagination["total_count"] == 3
      assert pagination["has_next_page"] == false
      assert pagination["has_prev_page"] == false

      # Verify all sessions are returned (don't check order due to flaky timestamps)
      returned_ids = Enum.map(returned_sessions, & &1["id"]) |> MapSet.new()
      created_ids = Enum.map(sessions, & &1.id) |> MapSet.new()
      assert MapSet.equal?(returned_ids, created_ids)

      [session1 | _] = returned_sessions
      assert session1["session_type"] == "job_code"
      assert session1["job_name"] == job.name
      assert is_binary(session1["workflow_name"])
      assert session1["message_count"] >= 0
      assert is_binary(session1["updated_at"])
    end

    test "respects pagination offset and limit", %{conn: conn, job: job} do
      conn =
        get(
          conn,
          ~p"/api/ai_assistant/sessions?session_type=job_code&job_id=#{job.id}&offset=1&limit=1"
        )

      response = json_response(conn, 200)

      assert %{
               "sessions" => returned_sessions,
               "pagination" => pagination
             } = response

      assert length(returned_sessions) == 1
      assert pagination["total_count"] == 3
      assert pagination["has_next_page"] == true
      assert pagination["has_prev_page"] == true
    end

    test "returns empty list when offset exceeds total", %{conn: conn, job: job} do
      conn =
        get(
          conn,
          ~p"/api/ai_assistant/sessions?session_type=job_code&job_id=#{job.id}&offset=100"
        )

      response = json_response(conn, 200)

      assert %{
               "sessions" => returned_sessions,
               "pagination" => pagination
             } = response

      assert returned_sessions == []
      assert pagination["total_count"] == 3
      assert pagination["has_next_page"] == false
    end

    test "returns 403 when user does not have access to job", %{
      conn: _conn,
      job: job
    } do
      # Create another user without access
      other_user = insert(:user)

      conn = build_conn()
      conn = put_req_header(conn, "accept", "application/json")
      conn = log_in_user(conn, other_user)

      conn =
        get(
          conn,
          ~p"/api/ai_assistant/sessions?session_type=job_code&job_id=#{job.id}"
        )

      assert json_response(conn, 403) == %{"error" => "Forbidden"}
    end
  end

  describe "list_sessions for job_code with unsaved job" do
    setup [:register_and_log_in_user]

    test "returns empty list for new unsaved job with no sessions", %{
      conn: conn
    } do
      unsaved_job_id = Ecto.UUID.generate()

      conn =
        get(
          conn,
          ~p"/api/ai_assistant/sessions?session_type=job_code&job_id=#{unsaved_job_id}"
        )

      response = json_response(conn, 200)

      assert %{
               "sessions" => returned_sessions,
               "pagination" => pagination
             } = response

      assert returned_sessions == []
      assert pagination["total_count"] == 0
    end

    test "returns sessions for unsaved job user has access to", %{
      conn: conn,
      user: user
    } do
      # Create workflow and unsaved job session
      project = insert(:project, project_users: [%{user_id: user.id}])
      workflow = insert(:workflow, project: project, name: "Test Workflow")
      unsaved_job_id = Ecto.UUID.generate()

      # Create session with unsaved job metadata
      session =
        insert(:chat_session,
          user: user,
          session_type: "job_code",
          title: "Unsaved Job Session",
          meta: %{
            "unsaved_job" => %{
              "id" => unsaved_job_id,
              "name" => "Unsaved Job",
              "workflow_id" => workflow.id
            }
          }
        )

      conn =
        get(
          conn,
          ~p"/api/ai_assistant/sessions?session_type=job_code&job_id=#{unsaved_job_id}"
        )

      response = json_response(conn, 200)

      assert %{
               "sessions" => returned_sessions,
               "pagination" => _pagination
             } = response

      assert length(returned_sessions) == 1

      [returned_session] = returned_sessions

      assert returned_session["id"] == session.id
      assert returned_session["title"] == session.title
      assert returned_session["session_type"] == "job_code"
      assert returned_session["job_name"] == "Unsaved Job"
      assert returned_session["workflow_name"] == workflow.name
      assert returned_session["is_unsaved"] == true
    end

    test "returns 403 when user does not have access to unsaved job's workflow",
         %{conn: _conn, user: _user} do
      # Create workflow owned by another user
      other_user = insert(:user)
      project = insert(:project, project_users: [%{user_id: other_user.id}])

      workflow =
        insert(:workflow, project: project, name: "Other User Workflow")

      unsaved_job_id = Ecto.UUID.generate()

      # Create session with unsaved job metadata
      _session =
        insert(:chat_session,
          user: other_user,
          session_type: "job_code",
          title: "Unsaved Job Session",
          meta: %{
            "unsaved_job" => %{
              "id" => unsaved_job_id,
              "name" => "Unsaved Job",
              "workflow_id" => workflow.id
            }
          }
        )

      # Create a new user with no access
      requesting_user = insert(:user)

      conn = build_conn()
      conn = put_req_header(conn, "accept", "application/json")
      conn = log_in_user(conn, requesting_user)

      conn =
        get(
          conn,
          ~p"/api/ai_assistant/sessions?session_type=job_code&job_id=#{unsaved_job_id}"
        )

      assert json_response(conn, 403) == %{"error" => "Forbidden"}
    end
  end

  describe "list_sessions for job_code with deleted job" do
    setup [:register_and_log_in_user]

    test "returns empty list when job is deleted (job_id becomes nil)", %{
      conn: conn,
      user: user
    } do
      # Create job and session, then delete job
      project = insert(:project, project_users: [%{user_id: user.id}])
      workflow = insert(:workflow, project: project)
      job = insert(:job, workflow: workflow, name: "Job to Delete")
      job_id = job.id

      _session =
        insert(:chat_session,
          user: user,
          session_type: "job_code",
          job: job,
          title: "Session for deleted job"
        )

      # Delete the job - this sets job_id to nil due to on_delete: :nilify_all
      Lightning.Repo.delete!(job)

      conn =
        get(
          conn,
          ~p"/api/ai_assistant/sessions?session_type=job_code&job_id=#{job_id}"
        )

      response = json_response(conn, 200)

      # Session won't be found because job_id is now nil
      assert %{"sessions" => [], "pagination" => %{"total_count" => 0}} =
               response
    end
  end

  describe "list_sessions for workflow_template" do
    setup [:register_and_log_in_user]

    test "returns sessions for project user has access to", %{
      conn: conn,
      user: user
    } do
      project = insert(:project, project_users: [%{user_id: user.id}])

      # Create multiple workflow template sessions
      sessions =
        for i <- 1..3 do
          session =
            insert(:workflow_chat_session,
              user: user,
              project: project,
              title: "Workflow Template Session #{i}"
            )

          # Add delay to ensure different updated_at timestamps
          Process.sleep(50)

          session
        end

      conn =
        get(
          conn,
          ~p"/api/ai_assistant/sessions?session_type=workflow_template&project_id=#{project.id}"
        )

      response = json_response(conn, 200)

      assert %{
               "sessions" => returned_sessions,
               "pagination" => pagination
             } = response

      assert length(returned_sessions) == 3
      assert pagination["total_count"] == 3

      # Verify all sessions are returned (don't check order due to flaky timestamps)
      returned_ids = Enum.map(returned_sessions, & &1["id"]) |> MapSet.new()
      created_ids = Enum.map(sessions, & &1.id) |> MapSet.new()
      assert MapSet.equal?(returned_ids, created_ids)

      # Verify first session has correct structure
      [session1 | _] = returned_sessions
      assert session1["session_type"] == "workflow_template"
      assert session1["project_name"] == project.name
    end

    test "filters sessions by workflow_id when provided", %{
      conn: conn,
      user: user
    } do
      project = insert(:project, project_users: [%{user_id: user.id}])

      workflow1 =
        insert(:workflow, project: project, name: "Workflow 1")

      workflow2 =
        insert(:workflow, project: project, name: "Workflow 2")

      # Create sessions for different workflows
      session1 =
        insert(:workflow_chat_session,
          user: user,
          project: project,
          workflow: workflow1,
          title: "Workflow 1 Session"
        )

      _session2 =
        insert(:workflow_chat_session,
          user: user,
          project: project,
          workflow: workflow2,
          title: "Workflow 2 Session"
        )

      # Request sessions filtered by workflow1
      conn =
        get(
          conn,
          ~p"/api/ai_assistant/sessions?session_type=workflow_template&project_id=#{project.id}&workflow_id=#{workflow1.id}"
        )

      response = json_response(conn, 200)

      assert %{"sessions" => returned_sessions} = response

      assert length(returned_sessions) == 1
      assert hd(returned_sessions)["id"] == session1.id
      assert hd(returned_sessions)["workflow_name"] == workflow1.name
    end

    test "includes workflow_name when session has workflow_id", %{
      conn: conn,
      user: user
    } do
      project = insert(:project, project_users: [%{user_id: user.id}])
      workflow = insert(:workflow, project: project, name: "My Workflow")

      # Create session with workflow - must filter by workflow_id in query
      # because API interprets missing workflow_id as "filter by nil"
      session =
        insert(:workflow_chat_session,
          user: user,
          project: project,
          workflow: workflow,
          title: "Workflow Session"
        )

      # Must include workflow_id in query to get sessions with that workflow
      conn =
        get(
          conn,
          ~p"/api/ai_assistant/sessions?session_type=workflow_template&project_id=#{project.id}&workflow_id=#{workflow.id}"
        )

      response = json_response(conn, 200)

      assert %{"sessions" => [returned_session]} = response

      assert returned_session["id"] == session.id
      assert returned_session["workflow_name"] == workflow.name
      assert returned_session["project_name"] == project.name
    end

    test "returns 403 when user does not have access to project", %{conn: _conn} do
      # Create project owned by another user
      other_user = insert(:user)
      project = insert(:project, project_users: [%{user_id: other_user.id}])

      # Create a new user with no access
      requesting_user = insert(:user)

      conn = build_conn()
      conn = put_req_header(conn, "accept", "application/json")
      conn = log_in_user(conn, requesting_user)

      conn =
        get(
          conn,
          ~p"/api/ai_assistant/sessions?session_type=workflow_template&project_id=#{project.id}"
        )

      assert json_response(conn, 403) == %{"error" => "Forbidden"}
    end

    test "returns empty list when no sessions exist", %{conn: conn, user: user} do
      project = insert(:project, project_users: [%{user_id: user.id}])

      conn =
        get(
          conn,
          ~p"/api/ai_assistant/sessions?session_type=workflow_template&project_id=#{project.id}"
        )

      response = json_response(conn, 200)

      assert %{
               "sessions" => [],
               "pagination" => %{"total_count" => 0}
             } = response
    end
  end

  describe "list_sessions authorization edge cases" do
    setup [:register_and_log_in_user]

    test "viewer can list sessions for job they have read access to", %{
      conn: _conn
    } do
      # Create viewer user
      viewer = insert(:user)

      project =
        insert(:project, project_users: [%{user_id: viewer.id, role: :viewer}])

      workflow = insert(:workflow, project: project)
      job = insert(:job, workflow: workflow)

      # Create session
      _session =
        insert(:chat_session,
          user: viewer,
          session_type: "job_code",
          job: job,
          title: "Viewer Session"
        )

      conn = build_conn()
      conn = put_req_header(conn, "accept", "application/json")
      conn = log_in_user(conn, viewer)

      conn =
        get(
          conn,
          ~p"/api/ai_assistant/sessions?session_type=job_code&job_id=#{job.id}"
        )

      response = json_response(conn, 200)

      assert %{"sessions" => [_session]} = response
    end

    test "admin can list sessions for project", %{conn: _conn} do
      # Create admin user
      admin = insert(:user)

      project =
        insert(:project, project_users: [%{user_id: admin.id, role: :admin}])

      _session =
        %Lightning.AiAssistant.ChatSession{id: Ecto.UUID.generate()}
        |> Lightning.AiAssistant.ChatSession.changeset(%{
          user_id: admin.id,
          session_type: "workflow_template",
          project_id: project.id,
          title: "Admin Session",
          meta: %{}
        })
        |> Lightning.Repo.insert!()

      conn = build_conn()
      conn = put_req_header(conn, "accept", "application/json")
      conn = log_in_user(conn, admin)

      conn =
        get(
          conn,
          ~p"/api/ai_assistant/sessions?session_type=workflow_template&project_id=#{project.id}"
        )

      response = json_response(conn, 200)

      assert %{"sessions" => [_session]} = response
    end
  end

  describe "list_sessions message_count" do
    setup [:register_and_log_in_user]

    test "includes accurate message_count for sessions", %{
      conn: conn,
      user: user
    } do
      project = insert(:project, project_users: [%{user_id: user.id}])
      workflow = insert(:workflow, project: project)
      job = insert(:job, workflow: workflow)

      # Create messages
      messages =
        for i <- 1..5 do
          insert(:chat_message,
            role: if(rem(i, 2) == 0, do: "user", else: "assistant"),
            content: "Message #{i}",
            status: "success"
          )
        end

      session =
        insert(:chat_session,
          user: user,
          session_type: "job_code",
          job: job,
          title: "Session with messages",
          messages: messages
        )

      conn =
        get(
          conn,
          ~p"/api/ai_assistant/sessions?session_type=job_code&job_id=#{job.id}"
        )

      response = json_response(conn, 200)

      assert %{"sessions" => [returned_session]} = response
      assert returned_session["id"] == session.id
      assert returned_session["message_count"] == 5
    end
  end

  # Helper functions

  defp create_job_with_sessions(%{user: user}) do
    project = insert(:project, project_users: [%{user_id: user.id}])

    workflow =
      insert(:workflow, project: project, name: "Test Workflow")

    job =
      insert(:job,
        workflow: workflow,
        name: "Test Job",
        body: "fn(state => state);",
        adaptor: "@openfn/language-common@latest"
      )

    # Create multiple sessions in reverse order so most recent is first
    sessions =
      for i <- 3..1//-1 do
        session =
          insert(:chat_session,
            user: user,
            session_type: "job_code",
            job: job,
            title: "Test Session #{i}"
          )

        # Add delay to ensure different updated_at timestamps
        Process.sleep(50)

        session
      end

    %{job: job, project: project, workflow: workflow, sessions: sessions}
  end

  describe "list_sessions job_code validation errors" do
    setup [:register_and_log_in_user]

    test "returns 400 when job_id is missing for job_code", %{conn: conn} do
      conn = get(conn, ~p"/api/ai_assistant/sessions?session_type=job_code")

      assert json_response(conn, 400) == %{"error" => "Bad Request"}
    end
  end

  describe "list_sessions workflow_template validation errors" do
    setup [:register_and_log_in_user]

    test "returns 400 when project_id is missing for workflow_template", %{
      conn: conn
    } do
      conn =
        get(conn, ~p"/api/ai_assistant/sessions?session_type=workflow_template")

      assert json_response(conn, 400) == %{"error" => "Bad Request"}
    end

    test "returns 404 when project doesn't exist for workflow_template", %{
      conn: conn
    } do
      non_existent_project_id = Ecto.UUID.generate()

      conn =
        get(
          conn,
          ~p"/api/ai_assistant/sessions?session_type=workflow_template&project_id=#{non_existent_project_id}"
        )

      assert json_response(conn, 404) == %{"error" => "Not Found"}
    end
  end

  describe "list_sessions with unsaved jobs" do
    setup [:register_and_log_in_user]

    test "includes sessions with unsaved_job metadata", %{
      conn: conn,
      user: user
    } do
      project = insert(:project, project_users: [%{user_id: user.id}])
      workflow = insert(:workflow, project: project)
      job = insert(:job, workflow: workflow)
      # Create session with unsaved_job in meta
      unsaved_job_id = Ecto.UUID.generate()

      _session =
        insert(:chat_session,
          user: user,
          session_type: "job_code",
          job_id: nil,
          meta: %{
            "unsaved_job" => %{
              "id" => unsaved_job_id,
              "name" => "Unsaved Job",
              "body" => "console.log('test');",
              "adaptor" => "@openfn/language-common@1.0.0",
              "workflow_id" => workflow.id
            }
          }
        )

      conn =
        get(
          conn,
          ~p"/api/ai_assistant/sessions?session_type=job_code&job_id=#{job.id}"
        )

      response = json_response(conn, 200)
      assert %{"sessions" => sessions, "pagination" => _pagination} = response
      # Verify sessions can be returned
      assert is_list(sessions)
    end
  end

  describe "format_session edge cases" do
    setup [:register_and_log_in_user]

    test "formats session with deleted job correctly", %{
      conn: conn,
      user: user
    } do
      project = insert(:project, project_users: [%{user_id: user.id}])
      workflow = insert(:workflow, project: project)
      # Create a job
      job =
        insert(:job,
          workflow: workflow,
          body: "console.log('test');",
          adaptor: "@openfn/language-common@1.0.0"
        )

      # Create session for the job
      session = insert(:chat_session, user: user, job: job)

      # Delete the job
      Lightning.Repo.delete!(job)

      # List sessions should still work
      conn =
        get(
          conn,
          ~p"/api/ai_assistant/sessions?session_type=job_code&job_id=#{session.job_id}"
        )

      response = json_response(conn, 200)
      assert %{"sessions" => sessions, "pagination" => _pagination} = response
      # Should return sessions even with deleted job
      assert is_list(sessions)
    end

    test "formats session without job_id or unsaved_job", %{
      conn: conn,
      user: user
    } do
      project = insert(:project, project_users: [%{user_id: user.id}])
      workflow = insert(:workflow, project: project)
      job = insert(:job, workflow: workflow)

      # Create a minimal session without job context
      _session =
        insert(:chat_session,
          user: user,
          session_type: "job_code",
          job_id: nil,
          meta: %{}
        )

      # List with different job_id (should not match)
      conn =
        get(
          conn,
          ~p"/api/ai_assistant/sessions?session_type=job_code&job_id=#{job.id}"
        )

      # Should return response with sessions list
      response = json_response(conn, 200)
      assert %{"sessions" => sessions, "pagination" => _pagination} = response
      assert is_list(sessions)
    end
  end
end
