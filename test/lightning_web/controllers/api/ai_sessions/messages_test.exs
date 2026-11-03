defmodule LightningWeb.API.AiSessions.MessagesTest do
  use LightningWeb.ConnCase, async: true

  import Lightning.Factories
  import Lightning.RaceHelpers, only: [after_first_query: 3]
  import LightningWeb.API.AiSessionHelpers
  import LightningWeb.API.ProblemHelpers

  alias Lightning.AiAssistant.ChatMessage
  alias Lightning.AiAssistant.MessageProcessor
  alias Lightning.Extensions.Message

  setup do
    ai_member(:viewer)
  end

  defp send_message(conn, session, body),
    do: post(conn, ~p"/api/ai_sessions/#{session.id}/messages", body)

  defp retry(conn, session, message),
    do:
      post(
        conn,
        ~p"/api/ai_sessions/#{session.id}/messages/#{message.id}/retries"
      )

  defp message_body(message, session_id) do
    %{
      "data" => %{
        "type" => "ai_messages",
        "id" => message.id,
        "attributes" => %{
          "id" => message.id,
          "role" => "user",
          "content" => message.content,
          "code" => nil,
          "status" => "pending",
          "inserted_at" => DateTime.to_iso8601(message.inserted_at)
        },
        "relationships" => %{
          "session" => %{
            "data" => %{"type" => "ai_sessions", "id" => session_id}
          }
        },
        "links" => %{"session" => ai_session_url(session_id)}
      }
    }
  end

  defp stub_spent_allowance(project_id) do
    Mox.stub(Lightning.Extensions.MockUsageLimiter, :limit_action, fn
      %{type: :ai_usage}, %{project_id: ^project_id} ->
        {:error, :ai_quota_spent, %Message{text: "No more queries"}}

      %{type: :ai_usage}, _context ->
        {:error, :exceeds_limit, %Message{text: "No more queries"}}
    end)
  end

  describe "sending a message" do
    test "a viewer's message is saved pending with what it attaches, queued, and answered 201",
         %{conn: conn, project: project, job: job, user: user} do
      session =
        insert(:chat_session,
          session_type: "job_code",
          job: job,
          project: project,
          user: user,
          meta: %{"runtime_context" => %{"job_body" => "held"}}
        )

      conn =
        send_message(conn, session, %{
          "content" => "And now?",
          "attach" => %{"code" => true}
        })

      %{"data" => %{"id" => id}} = body = json_response(conn, 201)
      message = Repo.get!(ChatMessage, id)

      assert body == message_body(message, session.id)

      assert {message.chat_session_id, message.user_id, message.role,
              message.status} == {session.id, user.id, :user, :pending}

      # The saved job is used, not what the session last held.
      assert message.meta == %{
               "message_options" => %{
                 "log" => false,
                 "attach_io_data" => false,
                 "step_id" => nil,
                 "send_code" => true
               },
               "runtime_context" => nil
             }

      assert_enqueued(worker: MessageProcessor, args: %{message_id: id})
    end

    test "to a session about a job not yet saved, sends the job with the message",
         %{conn: conn, workflow: workflow, user: user} do
      held = %{
        "id" => Ecto.UUID.generate(),
        "name" => "Draft",
        "body" => "fn()",
        "adaptor" => "@openfn/language-http@latest",
        "workflow_id" => workflow.id
      }

      session =
        insert(:chat_session,
          session_type: "job_code",
          workflow: workflow,
          user: user,
          meta: %{"unsaved_job" => held}
        )

      %{"data" => %{"id" => id}} =
        conn
        |> send_message(session, %{
          "content" => "Fix it",
          "context" => %{"body" => "fn(s => s)"}
        })
        |> json_response(201)

      assert Repo.get!(ChatMessage, id).meta["unsaved_job"] ==
               Map.put(held, "body", "fn(s => s)")
    end

    test "answers 422 with every problem in the body, writing nothing",
         %{conn: conn, project: project, workflow: workflow, user: user} do
      session = workflow_session(project, workflow, user)

      conn
      |> send_message(session, %{
        "content" => String.duplicate("x", 10_001),
        "context" => %{},
        "attach" => %{"logs" => true},
        "kind" => "job_code"
      })
      |> assert_problem(422, :invalid, [
        %{
          "pointer" => "#/kind",
          "code" => "unknown_key",
          "detail" => "is not accepted"
        },
        %{
          "pointer" => "#/content",
          "code" => "too_long",
          "detail" => "should be at most 10000 character(s)"
        },
        %{
          "pointer" => "#/context",
          "code" => "not_supported",
          "detail" => "is not supported for a workflow session"
        },
        %{
          "pointer" => "#/attach/logs",
          "code" => "not_supported",
          "detail" => "is not supported for a workflow session"
        }
      ])

      assert Repo.aggregate(ChatMessage, :count) == 0
    end

    test "answers 422 not_found for another project's run or step, writing nothing",
         %{conn: conn, project: project, job: job, user: user} do
      session =
        insert(:chat_session,
          session_type: "job_code",
          job: job,
          project: project,
          user: user
        )

      other_workflow = insert(:simple_workflow, project: insert(:project))

      {other_run, other_step} =
        run_with_step(other_workflow, hd(other_workflow.jobs))

      conn
      |> send_message(session, %{
        "content" => "What went wrong?",
        "attach" => %{
          "logs" => true,
          "run_id" => other_run.id,
          "io" => true,
          "step_id" => other_step.id
        }
      })
      |> assert_problem(422, :invalid, [
        %{
          "pointer" => "#/attach/run_id",
          "code" => "not_found",
          "detail" => "names nothing you can see"
        },
        %{
          "pointer" => "#/attach/step_id",
          "code" => "not_found",
          "detail" => "names nothing you can see"
        }
      ])

      assert Repo.aggregate(ChatMessage, :count) == 0
    end

    test "answers 402 when the project has used its AI allowance, writing nothing",
         %{conn: conn, project: project, workflow: workflow, user: user} do
      session = workflow_session(project, workflow, user)
      stub_spent_allowance(project.id)

      conn
      |> send_message(session, %{"content" => "Hi"})
      |> assert_problem(402, :exceeds_limit, [])

      assert Repo.aggregate(ChatMessage, :count) == 0
    end

    test "a session another request deletes mid-send answers 409 concurrent_edit",
         %{conn: conn, project: project, workflow: workflow, user: user} do
      session = workflow_session(project, workflow, user)

      # Loading the session's messages is the last read before the write.
      # The session's messages load in parallel tasks, out of the race
      # helper's sight, so the other request lands at the allowance check, the
      # last step before the write.
      Mox.stub(Lightning.Extensions.MockUsageLimiter, :limit_action, fn
        %{type: :ai_usage}, _context ->
          Repo.query!("DELETE FROM ai_chat_sessions WHERE id = $1", [
            Ecto.UUID.dump!(session.id)
          ])

          :ok
      end)

      conn
      |> send_message(session, %{"content" => "Hi"})
      |> assert_problem(409, :concurrent_edit, [])

      refute Repo.reload(session)
    end
  end

  describe "retrying a message" do
    test "sets a failed message back to pending, queues it, and answers 201",
         %{conn: conn, project: project, workflow: workflow, user: user} do
      session =
        workflow_session(project, workflow, user, [
          %{role: :user, status: :error, user: user}
        ])

      [failed] = session.messages

      conn = retry(conn, session, failed)
      retried = Repo.reload!(failed)

      assert json_response(conn, 201) == message_body(retried, session.id)
      assert retried.status == :pending
      assert_enqueued(worker: MessageProcessor, args: %{message_id: failed.id})
    end

    test "answers 409 not_retryable for a message that hasn't failed, or isn't a person's",
         %{conn: conn, project: project, workflow: workflow, user: user} do
      session =
        workflow_session(project, workflow, user, [
          %{role: :user, status: :pending},
          %{role: :user, status: :processing},
          %{role: :user, status: :success},
          %{role: :assistant, status: :error, user: nil}
        ])

      for message <- session.messages do
        conn
        |> retry(session, message)
        |> assert_problem(409, :not_retryable, [])

        assert Repo.reload!(message).status == message.status
      end

      refute_enqueued(worker: MessageProcessor)
    end

    test "answers 400 for a body that isn't an object, and 422 for any key",
         %{conn: conn, project: project, workflow: workflow, user: user} do
      session =
        workflow_session(project, workflow, user, [
          %{role: :user, status: :error}
        ])

      [failed] = session.messages
      path = ~p"/api/ai_sessions/#{session.id}/messages/#{failed.id}/retries"

      conn
      |> post(path, Jason.encode!([1]))
      |> assert_problem(400, :malformed, [])

      conn
      |> post(path, %{"content" => "x"})
      |> assert_problem(422, :invalid, [
        %{
          "pointer" => "#/content",
          "code" => "unknown_key",
          "detail" => "is not accepted"
        }
      ])

      assert Repo.reload!(failed).status == :error
    end

    test "answers 402 when the project has used its AI allowance, leaving the message failed",
         %{conn: conn, project: project, workflow: workflow, user: user} do
      session =
        workflow_session(project, workflow, user, [
          %{role: :user, status: :error}
        ])

      [failed] = session.messages
      stub_spent_allowance(project.id)

      conn |> retry(session, failed) |> assert_problem(402, :exceeds_limit, [])

      assert Repo.reload!(failed).status == :error
    end

    test "a message another request retries mid-retry answers 409 concurrent_edit and is queued once",
         %{conn: conn, project: project, workflow: workflow, user: user} do
      session =
        workflow_session(project, workflow, user, [
          %{role: :user, status: :error}
        ])

      [failed] = session.messages

      after_first_query("ai_chat_messages", failed.id, fn id ->
        Repo.query!(
          "UPDATE ai_chat_messages SET status = 'processing' WHERE id = $1",
          [id]
        )
      end)

      conn |> retry(session, failed) |> assert_problem(409, :concurrent_edit, [])

      assert Repo.reload!(failed).status == :processing
      refute_enqueued(worker: MessageProcessor)
    end
  end
end
