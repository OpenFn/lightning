defmodule LightningWeb.API.AiAssistantRefusalsTest do
  use LightningWeb.ConnCase, async: true

  import Lightning.Factories
  import LightningWeb.API.ProblemHelpers

  @moduletag :capture_log

  setup %{conn: conn} do
    {:ok, conn: put_req_header(conn, "accept", "application/json")}
  end

  setup :register_and_log_in_user

  @empty %{
    "sessions" => [],
    "pagination" => %{
      "total_count" => 0,
      "has_next_page" => false,
      "has_prev_page" => false
    }
  }

  describe "naming the sessions to list" do
    test "names a session type or target that is missing or not allowed", %{
      conn: conn
    } do
      for {query, parameter, code, detail} <- [
            {"job_id=123", "session_type", "required", "can't be blank"},
            {"session_type=invalid&job_id=123", "session_type", "not_allowed",
             "is invalid"},
            {"session_type=job_code", "job_id", "required", "can't be blank"},
            {"session_type=workflow_template", "project_id", "required",
             "can't be blank"}
          ] do
        conn
        |> get("/api/ai_assistant/sessions?" <> query)
        |> assert_problem(400, :invalid_parameter, [
          %{"parameter" => parameter, "code" => code, "detail" => detail}
        ])
      end
    end

    test "every bad parameter is reported at once", %{conn: conn, user: user} do
      project = insert(:project, project_users: [%{user_id: user.id}])

      conn
      |> get(~p"/api/ai_assistant/sessions",
        session_type: "workflow_template",
        project_id: project.id,
        offset: "-1",
        limit: "0",
        workflow_id: "nope"
      )
      |> assert_problem(400, :invalid_parameter, [
        %{
          "parameter" => "offset",
          "code" => "out_of_range",
          "detail" => "must be greater than or equal to 0"
        },
        %{
          "parameter" => "limit",
          "code" => "out_of_range",
          "detail" => "must be greater than 0"
        },
        %{
          "parameter" => "workflow_id",
          "code" => "type",
          "detail" => "is invalid"
        }
      ])

      conn
      |> get(~p"/api/ai_assistant/sessions", offset: "abc", limit: "x")
      |> assert_problem(400, :invalid_parameter, [
        %{
          "parameter" => "session_type",
          "code" => "required",
          "detail" => "can't be blank"
        },
        %{"parameter" => "offset", "code" => "type", "detail" => "is invalid"},
        %{"parameter" => "limit", "code" => "type", "detail" => "is invalid"}
      ])
    end

    test "no answer quotes a session_type, job_id or workflow_id it was sent",
         %{conn: conn, user: user} do
      project = insert(:project, project_users: [%{user_id: user.id}])

      params =
        plant_sentinel(%{
          "session_type" => "",
          "job_id" => "",
          "workflow_id" => ""
        })

      conn
      |> get(~p"/api/ai_assistant/sessions", params)
      |> refute_sentinel()
      |> assert_problem(400, :invalid_parameter, [
        %{
          "parameter" => "workflow_id",
          "code" => "type",
          "detail" => "is invalid"
        },
        %{
          "parameter" => "session_type",
          "code" => "not_allowed",
          "detail" => "is invalid"
        }
      ])

      conn
      |> get(
        ~p"/api/ai_assistant/sessions",
        Map.merge(params, %{
          "session_type" => "workflow_template",
          "project_id" => project.id
        })
      )
      |> refute_sentinel()
      |> assert_problem(400, :invalid_parameter, [
        %{
          "parameter" => "workflow_id",
          "code" => "type",
          "detail" => "is invalid"
        }
      ])

      conn
      |> get(
        ~p"/api/ai_assistant/sessions",
        Map.put(params, "session_type", "job_code")
      )
      |> refute_sentinel()
      |> assert_problem(400, :invalid_parameter, [
        not_a_uuid_entry(%{"parameter" => "job_id"})
      ])
    end
  end

  describe "who may reach it" do
    test "a job_id that isn't a UUID answers 400 naming it, and a project_id that isn't one 403, or to a superuser 400 naming it, 404 for an unknown one and 403 for one they aren't in",
         %{conn: conn} do
      superuser = log_in_user(build_conn(), insert(:user, role: :superuser))
      unknown = Ecto.UUID.generate()
      not_theirs = insert(:project).id

      for {caller, query, status, code, entries} <- [
            {conn, "session_type=job_code&job_id=nope", 400, :invalid_parameter,
             [
               not_a_uuid_entry(%{"parameter" => "job_id"})
             ]},
            {conn, "session_type=workflow_template&project_id=nope", 403,
             :forbidden, []},
            {superuser, "session_type=workflow_template&project_id=nope", 400,
             :invalid_parameter,
             [
               not_a_uuid_entry(%{"parameter" => "project_id"})
             ]},
            {superuser, "session_type=workflow_template&project_id=#{unknown}",
             404, :not_found, []},
            {superuser,
             "session_type=workflow_template&project_id=#{not_theirs}", 403,
             :forbidden, []}
          ] do
        caller
        |> put_req_header("accept", "application/json")
        |> get("/api/ai_assistant/sessions?" <> query)
        |> assert_problem(status, code, entries)
      end
    end

    test "a job_id is a filter: a job the caller can't see lists nothing, as an unknown one does, and only a malformed one is refused",
         %{conn: member, user: user} do
      stranger = log_in_user(build_conn(), insert(:user))
      owner = insert(:user)
      project = insert(:project, project_users: [%{user_id: user.id}])
      job = hd(insert(:simple_workflow, project: project).jobs)

      session =
        insert(:chat_session, user: user, session_type: "job_code", job: job)

      hidden = insert(:project, project_users: [%{user_id: owner.id}])
      hidden_workflow = insert(:simple_workflow, project: hidden)
      unsaved_job_id = Ecto.UUID.generate()

      insert(:chat_session,
        user: owner,
        session_type: "job_code",
        meta: %{
          "unsaved_job" => %{
            "id" => unsaved_job_id,
            "name" => "Unsaved",
            "workflow_id" => hidden_workflow.id
          }
        }
      )

      unknown = Ecto.UUID.generate()

      not_uuid = [
        not_a_uuid_entry(%{"parameter" => "job_id"})
      ]

      for {caller, job_id} <- [
            {stranger, job.id},
            {stranger, unknown},
            {stranger, unsaved_job_id},
            {member, unknown}
          ] do
        assert caller
               |> put_req_header("accept", "application/json")
               |> get(sessions_of(job_id))
               |> json_response(200) == @empty
      end

      for caller <- [stranger, member] do
        caller
        |> put_req_header("accept", "application/json")
        |> get(sessions_of("not-a-uuid"))
        |> assert_problem(400, :invalid_parameter, not_uuid)
      end

      assert %{"sessions" => [%{"id" => id}]} =
               member |> get(sessions_of(job.id)) |> json_response(200)

      assert id == session.id
    end

    test "a project that doesn't exist answers 403", %{conn: conn} do
      conn
      |> get(
        ~p"/api/ai_assistant/sessions?session_type=workflow_template&project_id=#{Ecto.UUID.generate()}"
      )
      |> assert_problem(403, :forbidden, [])
    end

    test "a caller who can't see the project gets 403 whatever the other parameters say",
         %{conn: conn} do
      project = insert(:project)

      conn
      |> get(
        ~p"/api/ai_assistant/sessions?session_type=workflow_template&project_id=#{project.id}"
      )
      |> assert_problem(403, :forbidden, [])

      conn
      |> get(~p"/api/ai_assistant/sessions",
        session_type: "workflow_template",
        project_id: project.id,
        offset: "abc",
        workflow_id: "nope"
      )
      |> assert_problem(403, :forbidden, [])
    end

    test "a member who hasn't met MFA is refused 403 on the project, and finds no sessions for its job",
         %{conn: conn, user: user} do
      project =
        insert(:project,
          requires_mfa: true,
          project_users: [%{user_id: user.id, role: :owner}]
        )

      workflow = insert(:simple_workflow, project: project)
      job = hd(workflow.jobs)

      conn
      |> get(
        ~p"/api/ai_assistant/sessions?session_type=workflow_template&project_id=#{project.id}"
      )
      |> assert_problem(403, :forbidden, [])

      assert conn
             |> get(
               ~p"/api/ai_assistant/sessions?session_type=job_code&job_id=#{job.id}"
             )
             |> json_response(200) == @empty
    end

    test "a project scheduled for deletion answers 409 to a member", %{
      conn: conn,
      user: user
    } do
      project =
        insert(:project,
          scheduled_deletion: ~U[2026-01-01 00:00:00Z],
          project_users: [%{user_id: user.id, role: :owner}]
        )

      conn
      |> get(
        ~p"/api/ai_assistant/sessions?session_type=workflow_template&project_id=#{project.id}"
      )
      |> assert_problem(409, :scheduled_for_deletion, [])
    end
  end

  defp sessions_of(job_id),
    do: "/api/ai_assistant/sessions?session_type=job_code&job_id=#{job_id}"
end
