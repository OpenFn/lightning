defmodule LightningWeb.API.AiSessions.ReadingTest do
  use LightningWeb.ConnCase, async: true

  import Ecto.Query
  import Lightning.Factories
  import LightningWeb.API.AiSessionHelpers
  import LightningWeb.API.ProblemHelpers

  setup do
    ai_member(:viewer)
  end

  defp list_url(project, query),
    do:
      "#{LightningWeb.Endpoint.url()}/api/projects/#{project.id}/ai_sessions?#{URI.encode_query(query)}"

  describe "listing a project's sessions" do
    test "about a workflow, saved or not yet saved, newest first, without their messages",
         %{conn: conn, project: project, workflow: workflow, user: user} do
      older =
        workflow_session(project, workflow, user, [
          %{role: :user, status: :success},
          %{role: :assistant, status: :success, user: nil},
          %{role: :user, status: :cancelled}
        ])
        |> Ecto.Changeset.change(updated_at: ~U[2026-01-01 00:00:00Z])
        |> Repo.update!()

      unsaved =
        insert(:chat_session,
          session_type: "workflow_template",
          project: project,
          user: user,
          meta: %{"unsaved_workflow" => %{"id" => workflow.id, "is_new" => true}}
        )

      # Neither is about this workflow: one is about another, one about none.
      workflow_session(project, insert(:workflow, project: project), user)
      workflow_session(project, nil, user)

      conn =
        get(
          conn,
          ~p"/api/projects/#{project.id}/ai_sessions?#{%{workflow_id: workflow.id}}"
        )

      page = list_url(project, page: 1, page_size: 10, workflow_id: workflow.id)

      assert json_response(conn, 200) == %{
               "data" =>
                 for {session, count} <- [{unsaved, 0}, {older, 2}] do
                   %{
                     "type" => "ai_sessions",
                     "id" => session.id,
                     "attributes" => %{
                       "title" => session.title,
                       "kind" => "workflow",
                       "job_id" => nil,
                       "workflow_id" => workflow.id,
                       "message_count" => count,
                       "inserted_at" => DateTime.to_iso8601(session.inserted_at),
                       "updated_at" => DateTime.to_iso8601(session.updated_at)
                     },
                     "relationships" => %{},
                     "links" => %{"self" => ai_session_url(session.id)}
                   }
                 end,
               "included" => [],
               "links" => %{
                 "self" => page,
                 "first" => page,
                 "last" => page,
                 "next" => nil,
                 "prev" => nil
               }
             }
    end

    test "about a job, saved or not yet saved, and none from another project",
         %{
           conn: conn,
           project: project,
           workflow: workflow,
           job: job,
           user: user
         } do
      saved =
        insert(:chat_session,
          session_type: "job_code",
          job: job,
          project: project,
          user: user
        )

      unsaved_id = Ecto.UUID.generate()

      unsaved =
        insert(:chat_session,
          session_type: "job_code",
          workflow: workflow,
          user: user,
          meta: %{
            "unsaved_job" => %{"id" => unsaved_id, "workflow_id" => workflow.id}
          }
        )

      other_workflow = insert(:workflow, project: insert(:project))

      insert(:chat_session,
        session_type: "job_code",
        workflow: other_workflow,
        user: user,
        meta: %{
          "unsaved_job" => %{
            "id" => unsaved_id,
            "workflow_id" => other_workflow.id
          }
        }
      )

      for {job_id, expected} <- [{job.id, [saved]}, {unsaved_id, [unsaved]}] do
        ids =
          conn
          |> get(
            ~p"/api/projects/#{project.id}/ai_sessions?#{%{job_id: job_id}}"
          )
          |> json_response(200)
          |> Map.fetch!("data")
          |> Enum.map(&{&1["id"], &1["attributes"]["job_id"]})

        assert ids == Enum.map(expected, &{&1.id, job_id})
      end
    end

    test "pages the sessions", %{
      conn: conn,
      project: project,
      workflow: workflow,
      user: user
    } do
      for _ <- 1..3, do: workflow_session(project, workflow, user)

      body =
        conn
        |> get(
          ~p"/api/projects/#{project.id}/ai_sessions?#{%{workflow_id: workflow.id, page: 2, page_size: 2}}"
        )
        |> json_response(200)

      query =
        &list_url(project, page: &1, page_size: 2, workflow_id: workflow.id)

      assert {length(body["data"]), body["links"]} ==
               {1,
                %{
                  "self" => query.(2),
                  "first" => query.(1),
                  "last" => query.(2),
                  "next" => nil,
                  "prev" => query.(1)
                }}
    end

    test "answers 400 invalid_parameter unless one of job_id and workflow_id is sent, as a UUID",
         %{conn: conn, project: project} do
      id = Ecto.UUID.generate()

      for {query, entries} <- [
            {%{},
             [
               %{
                 "parameter" => "job_id",
                 "code" => "required",
                 "detail" => "can't be blank unless workflow_id is sent"
               }
             ]},
            {%{job_id: id, workflow_id: id},
             [
               %{
                 "parameter" => "workflow_id",
                 "code" => "exclusive",
                 "detail" => "can't be sent with job_id"
               }
             ]},
            {plant_sentinel(%{job_id: nil, workflow_id: nil}),
             [
               not_a_uuid_entry(%{"parameter" => "job_id"}),
               not_a_uuid_entry(%{"parameter" => "workflow_id"})
             ]}
          ] do
        conn
        |> get(~p"/api/projects/#{project.id}/ai_sessions?#{query}")
        |> refute_sentinel()
        |> assert_problem(400, :invalid_parameter, entries)
      end
    end
  end

  describe "reading a session" do
    test "answers the session with its messages oldest first, leaving out cancelled ones",
         %{conn: conn, project: project, workflow: workflow, user: user} do
      session =
        workflow_session(project, workflow, user, [
          %{
            role: :user,
            status: :success,
            content: "Build it",
            inserted_at: ~U[2026-01-01 00:00:00Z]
          },
          %{
            role: :assistant,
            status: :success,
            user: nil,
            content: "Here",
            code: "jobs: {}",
            inserted_at: ~U[2026-01-01 00:00:01Z]
          },
          %{
            role: :user,
            status: :cancelled,
            content: "Never mind",
            inserted_at: ~U[2026-01-01 00:00:02Z]
          }
        ])

      [question, answer] =
        Repo.all(
          from m in Lightning.AiAssistant.ChatMessage,
            where: m.chat_session_id == ^session.id and m.status != :cancelled,
            order_by: m.inserted_at
        )

      conn = get(conn, ~p"/api/ai_sessions/#{session.id}")

      assert json_response(conn, 200) == %{
               "data" => %{
                 "type" => "ai_sessions",
                 "id" => session.id,
                 "attributes" => %{
                   "title" => session.title,
                   "kind" => "workflow",
                   "job_id" => nil,
                   "workflow_id" => workflow.id,
                   "message_count" => 2,
                   "messages" => [
                     %{
                       "id" => question.id,
                       "role" => "user",
                       "content" => "Build it",
                       "code" => nil,
                       "status" => "success",
                       "inserted_at" => "2026-01-01T00:00:00Z"
                     },
                     %{
                       "id" => answer.id,
                       "role" => "assistant",
                       "content" => "Here",
                       "code" => "jobs: {}",
                       "status" => "success",
                       "inserted_at" => "2026-01-01T00:00:01Z"
                     }
                   ],
                   "inserted_at" => DateTime.to_iso8601(session.inserted_at),
                   "updated_at" => DateTime.to_iso8601(session.updated_at)
                 },
                 "relationships" => %{},
                 "links" => %{"self" => ai_session_url(session.id)}
               },
               "included" => [],
               "links" => %{"self" => ai_session_url(session.id)}
             }
    end

    test "finds a job session's project through its job",
         %{conn: conn, job: job, user: user} do
      session =
        insert(:chat_session, session_type: "job_code", job: job, user: user)

      assert %{"data" => %{"id" => id, "attributes" => %{"kind" => "job_code"}}} =
               conn
               |> get(~p"/api/ai_sessions/#{session.id}")
               |> json_response(200)

      assert id == session.id
    end
  end
end
