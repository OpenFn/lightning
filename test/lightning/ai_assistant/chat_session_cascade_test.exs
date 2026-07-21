defmodule Lightning.AiAssistant.ChatSessionCascadeTest do
  use Lightning.DataCase, async: true

  alias Lightning.AiAssistant.ChatMessage
  alias Lightning.AiAssistant.ChatSession

  describe "foreign-key cascade" do
    test "deleting a job deletes its chat session and messages" do
      job = insert(:job)
      session = insert(:chat_session, session_type: "job_code", job: job)
      message = insert(:chat_message, chat_session: session, user: build(:user))

      Repo.delete!(job)

      refute Repo.get(ChatSession, session.id)
      refute Repo.get(ChatMessage, message.id)
    end

    test "deleting a workflow deletes its chat session" do
      workflow = insert(:workflow)

      session =
        insert(:chat_session,
          session_type: "workflow_template",
          job: nil,
          workflow: workflow
        )

      Repo.delete!(workflow)

      refute Repo.get(ChatSession, session.id)
    end
  end
end
