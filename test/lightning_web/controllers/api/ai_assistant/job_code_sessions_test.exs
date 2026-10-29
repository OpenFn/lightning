defmodule LightningWeb.API.AiAssistantJobCodeSessionsTest do
  use LightningWeb.ConnCase, async: true

  @moduletag :capture_log

  import Lightning.Factories
  import LightningWeb.ApiAiAssistantHelpers

  setup %{conn: conn} do
    {:ok, conn: put_req_header(conn, "accept", "application/json")}
  end

  describe "listing the sessions of a saved job" do
    setup [:register_and_log_in_user]

    test "answers each member of the project with the session document", %{
      conn: conn,
      user: user
    } do
      for role <- [:viewer, :editor, :admin, :owner] do
        project =
          insert(:project, project_users: [%{user_id: user.id, role: role}])

        workflow = insert(:workflow, project: project, name: "Test Workflow")
        job = insert(:job, workflow: workflow, name: "Test Job")

        session =
          insert(:chat_session,
            user: user,
            session_type: "job_code",
            job: job,
            title: "A #{role} session"
          )

        conn =
          get(
            conn,
            ~p"/api/ai_assistant/sessions?session_type=job_code&job_id=#{job.id}"
          )

        assert json_response(conn, 200) == %{
                 "sessions" => [
                   %{
                     "id" => session.id,
                     "title" => "A #{role} session",
                     "session_type" => "job_code",
                     "job_name" => "Test Job",
                     "workflow_name" => "Test Workflow",
                     "message_count" => 0,
                     "updated_at" => updated_at(session)
                   }
                 ],
                 "pagination" => pagination(1)
               },
               "a #{role} is answered the session"
      end
    end

    test "counts the messages of each session", %{conn: conn, user: user} do
      project = insert(:project, project_users: [%{user_id: user.id}])
      workflow = insert(:workflow, project: project)
      job = insert(:job, workflow: workflow)

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

      assert %{"sessions" => [returned_session]} = json_response(conn, 200)
      assert returned_session["id"] == session.id
      assert returned_session["message_count"] == 5
    end

    test "lists the sessions of the job asked for and no others", %{
      conn: conn,
      user: user
    } do
      project = insert(:project, project_users: [%{user_id: user.id}])
      workflow = insert(:workflow, project: project)
      job = insert(:job, workflow: workflow)

      insert(:chat_session,
        user: user,
        session_type: "job_code",
        job_id: nil,
        meta: %{
          "unsaved_job" => %{
            "id" => Ecto.UUID.generate(),
            "name" => "Unsaved Job",
            "workflow_id" => workflow.id
          }
        }
      )

      insert(:chat_session,
        user: user,
        session_type: "job_code",
        job_id: nil,
        meta: %{}
      )

      conn =
        get(
          conn,
          ~p"/api/ai_assistant/sessions?session_type=job_code&job_id=#{job.id}"
        )

      assert json_response(conn, 200) == %{
               "sessions" => [],
               "pagination" => pagination(0)
             }
    end
  end

  describe "paging the sessions of a saved job" do
    setup [:register_and_log_in_user, :create_job_with_sessions]

    test "lists every session when no paging is asked for", %{
      conn: conn,
      job: job,
      sessions: sessions
    } do
      conn =
        get(
          conn,
          ~p"/api/ai_assistant/sessions?session_type=job_code&job_id=#{job.id}"
        )

      assert %{"sessions" => returned_sessions, "pagination" => page} =
               json_response(conn, 200)

      assert MapSet.new(returned_sessions, & &1["id"]) ==
               MapSet.new(sessions, & &1.id)

      assert page == pagination(3)
    end

    test "respects pagination offset and limit", %{conn: conn, job: job} do
      conn =
        get(
          conn,
          ~p"/api/ai_assistant/sessions?session_type=job_code&job_id=#{job.id}&offset=1&limit=1"
        )

      assert %{"sessions" => [_one], "pagination" => page} =
               json_response(conn, 200)

      assert page == pagination(3, next: true, prev: true)
    end

    test "returns an empty list when the offset exceeds the total", %{
      conn: conn,
      job: job
    } do
      conn =
        get(
          conn,
          ~p"/api/ai_assistant/sessions?session_type=job_code&job_id=#{job.id}&offset=100"
        )

      assert json_response(conn, 200) == %{
               "sessions" => [],
               "pagination" => pagination(3, prev: true)
             }
    end

    test "lists nothing when the caller has no access to the job", %{job: job} do
      conn =
        build_conn()
        |> put_req_header("accept", "application/json")
        |> log_in_user(insert(:user))
        |> get(
          ~p"/api/ai_assistant/sessions?session_type=job_code&job_id=#{job.id}"
        )

      assert json_response(conn, 200) == %{
               "sessions" => [],
               "pagination" => pagination(0)
             }
    end
  end

  describe "listing the sessions of an unsaved job" do
    setup [:register_and_log_in_user]

    test "returns an empty list when the job has no sessions", %{conn: conn} do
      conn =
        get(
          conn,
          ~p"/api/ai_assistant/sessions?session_type=job_code&job_id=#{Ecto.UUID.generate()}"
        )

      assert json_response(conn, 200) == %{
               "sessions" => [],
               "pagination" => pagination(0)
             }
    end

    test "returns the session of a workflow the caller can reach", %{
      conn: conn,
      user: user
    } do
      project = insert(:project, project_users: [%{user_id: user.id}])
      workflow = insert(:workflow, project: project, name: "Test Workflow")
      unsaved_job_id = Ecto.UUID.generate()

      session =
        insert(:chat_session,
          user: user,
          session_type: "job_code",
          title: "Unsaved Job Session",
          workflow_id: workflow.id,
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

      assert json_response(conn, 200) == %{
               "sessions" => [
                 %{
                   "id" => session.id,
                   "title" => "Unsaved Job Session",
                   "session_type" => "job_code",
                   "job_name" => "Unsaved Job",
                   "workflow_name" => "Test Workflow",
                   "is_unsaved" => true,
                   "message_count" => 0,
                   "updated_at" => updated_at(session)
                 }
               ],
               "pagination" => pagination(1)
             }
    end

    test "returns the owner their session when it names no workflow", %{
      conn: conn,
      user: user
    } do
      unsaved_job_id = Ecto.UUID.generate()

      session =
        insert(:chat_session,
          user: user,
          session_type: "job_code",
          job_id: nil,
          title: "No-workflow unsaved session",
          meta: %{"unsaved_job" => %{"id" => unsaved_job_id, "name" => "X"}}
        )

      conn =
        get(
          conn,
          ~p"/api/ai_assistant/sessions?session_type=job_code&job_id=#{unsaved_job_id}"
        )

      assert json_response(conn, 200) == %{
               "sessions" => [
                 %{
                   "id" => session.id,
                   "title" => "No-workflow unsaved session",
                   "session_type" => "job_code",
                   "job_name" => "X",
                   "workflow_name" => nil,
                   "is_unsaved" => true,
                   "message_count" => 0,
                   "updated_at" => updated_at(session)
                 }
               ],
               "pagination" => pagination(1)
             }
    end

    test "lists nothing when the caller has no access to the unsaved job's workflow",
         %{conn: _conn} do
      other_user = insert(:user)
      project = insert(:project, project_users: [%{user_id: other_user.id}])

      workflow =
        insert(:workflow, project: project, name: "Other User Workflow")

      unsaved_job_id = Ecto.UUID.generate()

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

      conn =
        build_conn()
        |> put_req_header("accept", "application/json")
        |> log_in_user(insert(:user))
        |> get(
          ~p"/api/ai_assistant/sessions?session_type=job_code&job_id=#{unsaved_job_id}"
        )

      assert json_response(conn, 200) == %{
               "sessions" => [],
               "pagination" => pagination(0)
             }
    end

    test "lists nothing for a non-owner when the session names no workflow", %{
      conn: _conn
    } do
      unsaved_job_id = Ecto.UUID.generate()

      insert(:chat_session,
        user: insert(:user),
        session_type: "job_code",
        job_id: nil,
        title: "No-workflow unsaved session",
        meta: %{"unsaved_job" => %{"id" => unsaved_job_id, "name" => "X"}}
      )

      conn =
        build_conn()
        |> put_req_header("accept", "application/json")
        |> log_in_user(insert(:user))
        |> get(
          ~p"/api/ai_assistant/sessions?session_type=job_code&job_id=#{unsaved_job_id}"
        )

      assert json_response(conn, 200) == %{
               "sessions" => [],
               "pagination" => pagination(0)
             }
    end
  end

  describe "listing the sessions of a deleted job" do
    setup [:register_and_log_in_user]

    test "returns an empty list once the job is deleted", %{
      conn: conn,
      user: user
    } do
      project = insert(:project, project_users: [%{user_id: user.id}])
      workflow = insert(:workflow, project: project)
      job = insert(:job, workflow: workflow, name: "Job to Delete")
      job_id = job.id

      insert(:chat_session,
        user: user,
        session_type: "job_code",
        job: job,
        title: "Session for deleted job"
      )

      # Deleting the job nilifies the session's job_id, so nothing matches it.
      Lightning.Repo.delete!(job)

      conn =
        get(
          conn,
          ~p"/api/ai_assistant/sessions?session_type=job_code&job_id=#{job_id}"
        )

      assert json_response(conn, 200) == %{
               "sessions" => [],
               "pagination" => pagination(0)
             }
    end
  end

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

    sessions =
      for i <- 3..1//-1 do
        session =
          insert(:chat_session,
            user: user,
            session_type: "job_code",
            job: job,
            title: "Test Session #{i}"
          )

        # Distinct updated_at values, so the order the route sorts by is stable.
        Process.sleep(50)

        session
      end

    %{job: job, project: project, workflow: workflow, sessions: sessions}
  end
end
