defmodule LightningWeb.API.AiAssistantWorkflowTemplateSessionsTest do
  use LightningWeb.ConnCase, async: true

  @moduletag :capture_log

  import Lightning.Factories
  import LightningWeb.ApiAiAssistantHelpers

  setup %{conn: conn} do
    {:ok, conn: put_req_header(conn, "accept", "application/json")}
  end

  describe "listing the workflow template sessions of a project" do
    setup [:register_and_log_in_user]

    test "answers each member of the project with the session document", %{
      conn: conn,
      user: user
    } do
      for role <- [:viewer, :editor, :admin, :owner] do
        project =
          insert(:project,
            name: "Project of a #{role}",
            project_users: [%{user_id: user.id, role: role}]
          )

        session =
          insert(:workflow_chat_session,
            user: user,
            project: project,
            title: "A #{role} session"
          )

        conn =
          get(
            conn,
            ~p"/api/ai_assistant/sessions?session_type=workflow_template&project_id=#{project.id}"
          )

        assert json_response(conn, 200) == %{
                 "sessions" => [
                   %{
                     "id" => session.id,
                     "title" => "A #{role} session",
                     "session_type" => "workflow_template",
                     "project_name" => "Project of a #{role}",
                     "workflow_name" => nil,
                     "message_count" => 0,
                     "updated_at" => updated_at(session)
                   }
                 ],
                 "pagination" => pagination(1)
               },
               "a #{role} is answered the session"
      end
    end

    test "lists every session of the project", %{conn: conn, user: user} do
      project = insert(:project, project_users: [%{user_id: user.id}])

      sessions =
        for i <- 1..3 do
          insert(:workflow_chat_session,
            user: user,
            project: project,
            title: "Workflow Template Session #{i}"
          )
        end

      conn =
        get(
          conn,
          ~p"/api/ai_assistant/sessions?session_type=workflow_template&project_id=#{project.id}"
        )

      assert %{"sessions" => returned_sessions, "pagination" => page} =
               json_response(conn, 200)

      assert MapSet.new(returned_sessions, & &1["id"]) ==
               MapSet.new(sessions, & &1.id)

      assert page == pagination(3)
    end

    test "narrows the sessions to one workflow when workflow_id is given", %{
      conn: conn,
      user: user
    } do
      project =
        insert(:project,
          name: "My Project",
          project_users: [%{user_id: user.id}]
        )

      workflow1 = insert(:workflow, project: project, name: "Workflow 1")
      workflow2 = insert(:workflow, project: project, name: "Workflow 2")

      session1 =
        insert(:workflow_chat_session,
          user: user,
          project: project,
          workflow: workflow1,
          title: "Workflow 1 Session"
        )

      insert(:workflow_chat_session,
        user: user,
        project: project,
        workflow: workflow2,
        title: "Workflow 2 Session"
      )

      conn =
        get(
          conn,
          ~p"/api/ai_assistant/sessions?session_type=workflow_template&project_id=#{project.id}&workflow_id=#{workflow1.id}"
        )

      assert json_response(conn, 200) == %{
               "sessions" => [
                 %{
                   "id" => session1.id,
                   "title" => "Workflow 1 Session",
                   "session_type" => "workflow_template",
                   "project_name" => "My Project",
                   "workflow_name" => "Workflow 1",
                   "message_count" => 0,
                   "updated_at" => updated_at(session1)
                 }
               ],
               "pagination" => pagination(1)
             }
    end

    test "returns an empty list when the project has no sessions", %{
      conn: conn,
      user: user
    } do
      project = insert(:project, project_users: [%{user_id: user.id}])

      conn =
        get(
          conn,
          ~p"/api/ai_assistant/sessions?session_type=workflow_template&project_id=#{project.id}"
        )

      assert json_response(conn, 200) == %{
               "sessions" => [],
               "pagination" => pagination(0)
             }
    end
  end
end
