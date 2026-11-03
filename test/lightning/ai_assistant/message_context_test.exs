defmodule Lightning.AiAssistant.MessageContextTest do
  @moduledoc """
  A message that carries its own attachments and editor context is answered,
  and retried, with what it sent, over what the session last held. Messages
  that carry neither keep the session's.
  """
  use Lightning.DataCase, async: true

  import Lightning.Factories

  alias Lightning.AiAssistant
  alias Lightning.AiAssistant.MessageProcessor

  @moduletag :capture_log

  setup do
    Process.put(:oban_testing, :manual)

    Mox.stub(Lightning.MockConfig, :apollo, fn
      :endpoint -> "http://localhost:3000"
      :ai_assistant_api_key -> "test_api_key"
      :connect_timeout -> 1_000
      :idle_timeout -> 5_000
      :request_timeout -> 5_000
    end)

    respond =
      Lightning.AiAssistantHelpers.streaming_or_sync_response(%{
        "response" => "AI response",
        "history" => []
      })

    test = self()

    Mox.stub(Lightning.Tesla.Mock, :call, fn env, opts ->
      send(test, {:apollo, env.url, Jason.decode!(env.body)})
      respond.(env, opts)
    end)

    Mox.stub(Lightning.Extensions.MockUsageLimiter, :increment_ai_usage, fn _,
                                                                            _ ->
      Ecto.Multi.new()
    end)

    user = insert(:user)
    project = insert(:project, project_users: [%{user: user, role: :owner}])
    workflow = insert(:workflow, project: project)
    job = insert(:job, workflow: workflow, body: "saved body")

    session =
      insert(:chat_session,
        session_type: "job_code",
        job: job,
        project: project,
        user: user,
        meta: %{
          "runtime_context" => %{"job_body" => "held body"},
          "message_options" => %{"log" => false, "attach_io_data" => false}
        }
      )

    %{
      user: user,
      project: project,
      workflow: workflow,
      session: session,
      job: job
    }
  end

  defp ask(session, user, meta) do
    {:ok, message} =
      AiAssistant.add_message(session, %{content: "Help", user: user, meta: meta})

    :ok = perform_job(MessageProcessor, %{"message_id" => message.id})
    assert_receive {:apollo, _url, payload}
    payload["context"]
  end

  test "a message that says not to send the code leaves out the job's code",
       %{session: session, user: user} do
    context =
      ask(session, user, %{
        "message_options" => %{"send_code" => false},
        "runtime_context" => nil
      })

    refute Map.has_key?(context, "expression")
  end

  test "a message's editor context, or its saying there is none, wins over what the session held",
       %{session: session, user: user} do
    assert ask(session, user, %{
             "message_options" => %{"send_code" => true},
             "runtime_context" => %{"job_body" => "editor body"}
           })["expression"] == "editor body"

    assert ask(session, user, %{
             "message_options" => %{"send_code" => true},
             "runtime_context" => nil
           })["expression"] == "saved body"
  end

  test "a message with no context of its own keeps the session's",
       %{session: session, user: user} do
    assert ask(session, user, %{})["expression"] == "held body"
  end

  test "a retried message is asked with what it sent the first time",
       %{session: session, user: user} do
    {:ok, message} =
      AiAssistant.add_message(session, %{
        content: "Help",
        user: user,
        meta: %{
          "message_options" => %{"send_code" => true},
          "runtime_context" => %{"job_body" => "first body"}
        }
      })

    message |> Ecto.Changeset.change(status: :error) |> Repo.update!()

    # The session moves on before the retry.
    session
    |> Ecto.Changeset.change(
      meta: %{"runtime_context" => %{"job_body" => "later"}}
    )
    |> Repo.update!()

    {:ok, _retried} = AiAssistant.retry_failed_message(Repo.reload!(message))
    :ok = perform_job(MessageProcessor, %{"message_id" => message.id})

    assert_receive {:apollo, _url,
                    %{"context" => %{"expression" => "first body"}}}
  end

  describe "a session about a job not yet saved" do
    setup %{project: project, workflow: workflow, job: job} do
      step =
        insert(:step,
          job: job,
          input_dataclip:
            build(:dataclip, project: project, body: %{"patient" => "Ada"}),
          output_dataclip: build(:dataclip, project: project, body: %{"ok" => 1})
        )

      unsaved_job = %{
        "id" => Ecto.UUID.generate(),
        "name" => "Draft",
        "body" => "fn(s => s)",
        "adaptor" => "@openfn/language-common@latest",
        "workflow_id" => workflow.id
      }

      %{step: step, unsaved_job: unsaved_job}
    end

    test "is started in its workflow's project, and sends a step's input and output",
         %{user: user, project: project, step: step, unsaved_job: unsaved_job} do
      {:ok, session} =
        AiAssistant.create_session_for_unsaved_job(
          user,
          "Help",
          %{"unsaved_job" => unsaved_job},
          message_meta: %{
            "unsaved_job" => unsaved_job,
            "message_options" => %{
              "attach_io_data" => true,
              "step_id" => step.id
            }
          }
        )

      assert session.project_id == project.id

      [message] = session.messages
      :ok = perform_job(MessageProcessor, %{"message_id" => message.id})

      assert_receive {:apollo, _url, %{"context" => context}}

      assert {context["input"], context["output"]} ==
               {%{"patient" => "string"}, %{"ok" => "number"}}
    end

    test "stored without a project still sends a step's input and output",
         %{user: user, workflow: workflow, step: step, unsaved_job: unsaved_job} do
      session =
        insert(:chat_session,
          session_type: "job_code",
          workflow: workflow,
          project: nil,
          user: user,
          meta: %{"unsaved_job" => unsaved_job}
        )

      context =
        ask(session, user, %{
          "unsaved_job" => unsaved_job,
          "message_options" => %{"attach_io_data" => true, "step_id" => step.id}
        })

      assert {context["input"], context["output"]} ==
               {%{"patient" => "string"}, %{"ok" => "number"}}
    end
  end
end
