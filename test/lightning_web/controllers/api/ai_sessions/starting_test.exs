defmodule LightningWeb.API.AiSessions.StartingTest do
  use LightningWeb.ConnCase, async: true

  import Ecto.Query
  import Lightning.Factories
  import LightningWeb.API.SessionHelpers
  import Lightning.RaceHelpers
  import LightningWeb.API.AiSessionHelpers
  import LightningWeb.API.ProblemHelpers

  alias Lightning.AiAssistant.ChatMessage
  alias Lightning.AiAssistant.ChatSession
  alias Lightning.AiAssistant.MessageProcessor
  alias Lightning.Extensions.Message

  setup do
    ai_member()
  end

  defp start(conn, project, body),
    do: post(conn, ~p"/api/projects/#{project.id}/ai_sessions", body)

  defp only_message(session_id) do
    [message] =
      Repo.all(from m in ChatMessage, where: m.chat_session_id == ^session_id)

    message
  end

  @no_attach %{
    "message_options" => %{
      "log" => false,
      "attach_io_data" => false,
      "step_id" => nil,
      "send_code" => false
    }
  }

  describe "starting a session" do
    test "about a saved job, answers 201 with the session and its first message pending, and queues it",
         %{conn: conn, project: project, job: job, user: user} do
      conn =
        start(conn, project, %{
          "kind" => "job_code",
          "job_id" => job.id,
          "message" => %{
            "content" => "Map patients to FHIR",
            "context" => %{"body" => "fn(state => state.patients)"},
            "attach" => %{"code" => true}
          }
        })

      %{"data" => %{"id" => id}} = body = json_response(conn, 201)
      session = Repo.get!(ChatSession, id)
      message = only_message(id)

      assert body == %{
               "data" => %{
                 "type" => "ai_sessions",
                 "id" => id,
                 "attributes" => %{
                   "title" => "Map patients to FHIR",
                   "kind" => "job_code",
                   "job_id" => job.id,
                   "workflow_id" => nil,
                   "message_count" => 1,
                   "messages" => [
                     %{
                       "id" => message.id,
                       "role" => "user",
                       "content" => "Map patients to FHIR",
                       "code" => nil,
                       "status" => "pending",
                       "inserted_at" => DateTime.to_iso8601(message.inserted_at)
                     }
                   ],
                   "inserted_at" => DateTime.to_iso8601(session.inserted_at),
                   "updated_at" => DateTime.to_iso8601(session.updated_at)
                 },
                 "relationships" => %{},
                 "links" => %{"self" => ai_session_url(id)}
               },
               "included" => [],
               "links" => %{"self" => ai_session_url(id)}
             }

      assert {session.session_type, session.job_id, session.project_id,
              session.user_id} == {"job_code", job.id, project.id, user.id}

      assert message.meta == %{
               "message_options" => %{
                 "log" => false,
                 "attach_io_data" => false,
                 "step_id" => nil,
                 "send_code" => true
               },
               "runtime_context" => %{
                 "job_name" => job.name,
                 "job_body" => "fn(state => state.patients)",
                 "job_adaptor" => job.adaptor
               }
             }

      assert_enqueued(worker: MessageProcessor, args: %{message_id: message.id})
    end

    test "about a job not yet saved, keeps the job from the message's context",
         %{conn: conn, project: project, workflow: workflow} do
      job_id = Ecto.UUID.generate()

      conn =
        start(conn, project, %{
          "kind" => "job_code",
          "job_id" => job_id,
          "workflow_id" => workflow.id,
          "message" => %{
            "content" => "Help",
            "context" => %{"name" => "New step", "body" => "fn()"}
          }
        })

      %{"data" => %{"id" => id, "attributes" => attributes}} =
        json_response(conn, 201)

      assert Map.take(attributes, ["kind", "job_id", "workflow_id"]) == %{
               "kind" => "job_code",
               "job_id" => job_id,
               "workflow_id" => workflow.id
             }

      unsaved_job = %{
        "id" => job_id,
        "name" => "New step",
        "body" => "fn()",
        "adaptor" => "@openfn/language-common@latest",
        "workflow_id" => workflow.id
      }

      assert Repo.get!(ChatSession, id).meta == %{"unsaved_job" => unsaved_job}

      assert only_message(id).meta ==
               Map.put(@no_attach, "unsaved_job", unsaved_job)
    end

    test "about a saved workflow, an unsaved one, or none yet",
         %{conn: conn, project: project, workflow: workflow} do
      unsaved_id = Ecto.UUID.generate()

      for {workflow_id, stored_workflow_id, meta} <- [
            {workflow.id, workflow.id, %{}},
            {unsaved_id, nil,
             %{"unsaved_workflow" => %{"id" => unsaved_id, "is_new" => true}}},
            {nil, nil, %{}}
          ] do
        body =
          %{"kind" => "workflow", "message" => %{"content" => "Build it"}}
          |> then(
            &if(workflow_id,
              do: Map.put(&1, "workflow_id", workflow_id),
              else: &1
            )
          )

        %{"data" => %{"id" => id, "attributes" => attributes}} =
          conn |> start(project, body) |> json_response(201)

        session = Repo.get!(ChatSession, id)

        assert {attributes["kind"], attributes["workflow_id"]} ==
                 {"workflow", workflow_id}

        assert {session.session_type, session.workflow_id, session.meta} ==
                 {"workflow_template", stored_workflow_id, meta}

        assert only_message(id).meta == @no_attach
      end
    end

    test "with logs from a run and input and output from a step of the project, stores them on the message",
         %{conn: conn, project: project, workflow: workflow, job: job} do
      {run, step} = run_with_step(workflow, job)

      conn =
        start(conn, project, %{
          "kind" => "job_code",
          "job_id" => job.id,
          "message" => %{
            "content" => "Why did it fail?",
            "attach" => %{
              "logs" => true,
              "io" => true,
              "run_id" => run.id,
              "step_id" => step.id
            }
          }
        })

      %{"data" => %{"id" => id}} = json_response(conn, 201)

      assert only_message(id).meta == %{
               "message_options" => %{
                 "log" => true,
                 "attach_io_data" => true,
                 "step_id" => step.id,
                 "send_code" => false
               },
               "follow_run_id" => run.id,
               "runtime_context" => nil
             }
    end
  end

  describe "refusals" do
    test "answers 422 with every problem in the body at once, writing nothing",
         %{conn: conn, project: project} do
      conn
      |> start(project, %{
        "kind" => "chat",
        "job_id" => "nope",
        "extra" => 1,
        "message" => %{
          "content" => "",
          "context" => "editor",
          "attach" => %{"logs" => "yes", "run_id" => "nope", "other" => true}
        }
      })
      |> refute_sentinel()
      |> assert_problem(422, :invalid, [
        %{
          "pointer" => "#/extra",
          "code" => "unknown_key",
          "detail" => "is not accepted"
        },
        %{
          "pointer" => "#/kind",
          "code" => "not_allowed",
          "detail" => "is invalid"
        },
        not_a_uuid_entry(%{"pointer" => "#/job_id"}),
        %{
          "pointer" => "#/message/content",
          "code" => "required",
          "detail" => "can't be blank"
        },
        %{
          "pointer" => "#/message/context",
          "code" => "type",
          "detail" => "is not an object"
        },
        %{
          "pointer" => "#/message/attach/other",
          "code" => "unknown_key",
          "detail" => "is not accepted"
        },
        %{
          "pointer" => "#/message/attach/logs",
          "code" => "type",
          "detail" => "is not a boolean"
        },
        not_a_uuid_entry(%{"pointer" => "#/message/attach/run_id"})
      ])

      assert Repo.aggregate(ChatSession, :count) == 0
    end

    test "answers 422 for what a kind of session needs or can't take",
         %{conn: conn, project: project, workflow: workflow, job: job} do
      other_project = insert(:project)
      other_workflow = insert(:simple_workflow, project: other_project)

      {other_run, _other_step} =
        run_with_step(other_workflow, hd(other_workflow.jobs))

      message = %{"content" => "Hi"}

      for {body, entries} <- [
            {%{"message" => message},
             [
               %{
                 "pointer" => "#/kind",
                 "code" => "required",
                 "detail" => "can't be blank"
               }
             ]},
            {%{"kind" => "job_code"},
             [
               %{
                 "pointer" => "#/job_id",
                 "code" => "required",
                 "detail" => "can't be blank"
               },
               %{
                 "pointer" => "#/message",
                 "code" => "required",
                 "detail" => "can't be blank"
               }
             ]},
            {%{
               "kind" => "job_code",
               "job_id" => Ecto.UUID.generate(),
               "message" => message
             },
             [
               %{
                 "pointer" => "#/workflow_id",
                 "code" => "required",
                 "detail" => "can't be blank"
               },
               %{
                 "pointer" => "#/message/context/name",
                 "code" => "required",
                 "detail" => "can't be blank for a job not yet saved"
               }
             ]},
            {%{
               "kind" => "job_code",
               "job_id" => Ecto.UUID.generate(),
               "workflow_id" => other_workflow.id,
               "message" => Map.put(message, "context", %{"name" => "New"})
             },
             [
               %{
                 "pointer" => "#/workflow_id",
                 "code" => "not_found",
                 "detail" => "names nothing you can see"
               }
             ]},
            {%{
               "kind" => "job_code",
               "job_id" => job.id,
               "workflow_id" => insert(:workflow, project: project).id,
               "message" => message
             },
             [
               %{
                 "pointer" => "#/workflow_id",
                 "code" => "mismatch",
                 "detail" => "is not the job's workflow"
               }
             ]},
            {%{
               "kind" => "job_code",
               "job_id" => job.id,
               "message" =>
                 Map.put(message, "attach", %{"logs" => true, "io" => true})
             },
             [
               %{
                 "pointer" => "#/message/attach/run_id",
                 "code" => "required",
                 "detail" => "can't be blank"
               },
               %{
                 "pointer" => "#/message/attach/step_id",
                 "code" => "required",
                 "detail" => "can't be blank"
               }
             ]},
            {%{
               "kind" => "job_code",
               "job_id" => job.id,
               "message" =>
                 Map.put(message, "attach", %{
                   "logs" => true,
                   "run_id" => other_run.id
                 })
             },
             [
               %{
                 "pointer" => "#/message/attach/run_id",
                 "code" => "not_found",
                 "detail" => "names nothing you can see"
               }
             ]},
            {%{
               "kind" => "workflow",
               "job_id" => job.id,
               "workflow_id" => workflow.id,
               "message" =>
                 message
                 |> Map.put("context", %{"name" => "x"})
                 |> Map.put("attach", %{"io" => true})
             },
             [
               %{
                 "pointer" => "#/job_id",
                 "code" => "not_allowed",
                 "detail" => "can't be sent with a workflow session"
               },
               %{
                 "pointer" => "#/message/context",
                 "code" => "not_supported",
                 "detail" => "is not supported for a workflow session"
               },
               %{
                 "pointer" => "#/message/attach/io",
                 "code" => "not_supported",
                 "detail" => "is not supported for a workflow session"
               }
             ]}
          ] do
        conn |> start(project, body) |> assert_problem(422, :invalid, entries)
      end

      assert Repo.aggregate(ChatSession, :count) == 0
    end

    test "answers 400 malformed for a body that isn't an object",
         %{conn: conn, project: project} do
      conn
      |> start(project, Jason.encode!(["x"]))
      |> assert_problem(400, :malformed, [])
    end

    test "answers 402 when the project has used its AI allowance, writing nothing",
         %{conn: conn, project: project} do
      project_id = project.id

      Mox.stub(Lightning.Extensions.MockUsageLimiter, :limit_action, fn
        %{type: :ai_usage}, %{project_id: ^project_id} ->
          {:error, :ai_quota_spent, %Message{text: "No more queries"}}

        %{type: :ai_usage}, _context ->
          {:error, :exceeds_limit, %Message{text: "No more queries"}}
      end)

      conn
      |> start(project, %{
        "kind" => "workflow",
        "message" => %{"content" => "Hi"}
      })
      |> assert_problem(402, :exceeds_limit, [])

      assert Repo.aggregate(ChatSession, :count) == 0
    end
  end

  describe "stale writes" do
    test "a project another request deletes mid-start answers 409 concurrent_edit",
         %{user: user} do
      project = insert(:project, project_users: [%{user: user, role: :editor}])
      delete_project_mid_save(project.id)

      session_conn(build_conn(), user)
      |> start(project, %{
        "kind" => "workflow",
        "message" => %{"content" => "Hi"}
      })
      |> assert_problem(409, :concurrent_edit, [])

      refute Repo.reload(project)
      assert Repo.aggregate(ChatSession, :count) == 0
    end
  end

  defp run_with_step(workflow, job) do
    work_order =
      insert(:workorder, workflow: workflow, dataclip: insert(:dataclip))

    run =
      insert(:run,
        work_order: work_order,
        dataclip: work_order.dataclip,
        starting_job: job
      )

    step = insert(:step, job: job, runs: [run])
    {run, step}
  end
end
