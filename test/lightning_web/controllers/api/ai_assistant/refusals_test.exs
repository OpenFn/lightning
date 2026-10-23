defmodule LightningWeb.API.AiAssistantRefusalsTest do
  use LightningWeb.ConnCase, async: true

  @moduletag :capture_log

  import Lightning.Factories
  import LightningWeb.API.ProblemHelpers

  setup %{conn: conn} do
    {:ok, conn: put_req_header(conn, "accept", "application/json")}
  end

  setup :register_and_log_in_user

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
      |> assert_problem(404, :not_found, [])
    end
  end

  describe "who may reach it" do
    test "a job_id or project_id that isn't a UUID answers 404", %{conn: conn} do
      conn
      |> get(~p"/api/ai_assistant/sessions?session_type=job_code&job_id=nope")
      |> assert_problem(404, :not_found, [])

      conn
      |> get(
        ~p"/api/ai_assistant/sessions?session_type=workflow_template&project_id=nope"
      )
      |> assert_problem(404, :not_found, [])
    end

    test "a project that doesn't exist answers 404", %{conn: conn} do
      conn
      |> get(
        ~p"/api/ai_assistant/sessions?session_type=workflow_template&project_id=#{Ecto.UUID.generate()}"
      )
      |> assert_problem(404, :not_found, [])
    end

    test "a caller who can't see the project gets 404 whatever the other parameters say",
         %{conn: conn} do
      project = insert(:project)

      conn
      |> get(
        ~p"/api/ai_assistant/sessions?session_type=workflow_template&project_id=#{project.id}"
      )
      |> assert_problem(404, :not_found, [])

      conn
      |> get(~p"/api/ai_assistant/sessions",
        session_type: "workflow_template",
        project_id: project.id,
        offset: "abc",
        workflow_id: "nope"
      )
      |> assert_problem(404, :not_found, [])
    end

    test "a member who hasn't met MFA is refused 403", %{conn: conn, user: user} do
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

      conn
      |> get(
        ~p"/api/ai_assistant/sessions?session_type=job_code&job_id=#{job.id}"
      )
      |> assert_problem(403, :forbidden, [])
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
end
