defmodule Lightning.AiAssistant.MessageProcessorTest do
  use Lightning.DataCase, async: true

  import Mox
  import Lightning.Factories

  alias Lightning.AiAssistant
  alias Lightning.AiAssistant.MessageProcessor

  # Note: Integration tests for I/O data scrubbing are tested at lower levels:
  #
  # - test/lightning_web/channels/ai_assistant_channel_test.exs
  #   Tests that attach_io_data and step_id are extracted from params and stored in session meta
  #
  # - test/lightning/ai_assistant/ai_assistant_test.exs
  #   Tests that input and output options are included in the Apollo context
  #
  # The message processor's fetch_and_scrub_io_data/1 logic in
  # lib/lightning/ai_assistant/message_processor.ex is verified through these lower-level tests.
  # Full end-to-end integration testing of dataclip persistence is challenging in the test
  # environment due to test database constraints with map-type columns.

  setup :verify_on_exit!

  setup do
    Mox.stub(Lightning.MockConfig, :apollo, fn key ->
      case key do
        :endpoint -> "http://localhost:3000"
        :ai_assistant_api_key -> "test_api_key"
        :timeout -> 5_000
      end
    end)

    Mox.stub(Lightning.Tesla.Mock, :call, fn %{method: :post}, _opts ->
      {:ok,
       %Tesla.Env{
         status: 200,
         body: %{
           "response" => "AI response",
           "history" => [
             %{"role" => "user", "content" => "test"},
             %{"role" => "assistant", "content" => "AI response"}
           ]
         }
       }}
    end)

    Mox.stub(Lightning.Extensions.MockUsageLimiter, :limit_action, fn _, _ ->
      :ok
    end)

    Mox.stub(
      Lightning.Extensions.MockUsageLimiter,
      :increment_ai_usage,
      fn _, _ -> Ecto.Multi.new() end
    )

    user = insert(:user)
    project = insert(:project, project_users: [%{user: user, role: :owner}])
    [user: user, project: project]
  end

  describe "update_session_with_job_context/2" do
    @tag :capture_log
    test "sets session.job_id from message and routes to job chat processing", %{
      user: user,
      project: project
    } do
      workflow = insert(:workflow, project: project)
      job = insert(:job, workflow: workflow)

      # workflow_template session with no job_id — the session alone is not a job chat
      session =
        insert(:chat_session,
          user: user,
          session_type: "workflow_template",
          project: project,
          workflow: workflow,
          job_id: nil,
          meta: %{}
        )

      # User message carries job_id (e.g. sent while focused on a saved job)
      {:ok, updated_session} =
        AiAssistant.save_message(
          session,
          %{role: :user, content: "help with this job", user: user, job: job},
          []
        )

      user_message = Enum.find(updated_session.messages, &(&1.role == :user))
      assert user_message.job_id == job.id

      # update_session_with_job_context overwrites session.job_id with
      # message.job_id, so job_chat? returns true and process_job_message runs
      assert :ok =
               perform_job(MessageProcessor, %{"message_id" => user_message.id})

      reloaded = AiAssistant.get_session!(session.id)
      assistant_message = Enum.find(reloaded.messages, &(&1.role == :assistant))

      # process_job_message enriches the session with the job and saves the
      # assistant reply with job_id set via maybe_put_job_id_from_session
      assert assistant_message != nil
      assert assistant_message.job_id == job.id
    end

    @tag :capture_log
    test "copies unsaved_job from message meta into session meta and routes to job chat processing",
         %{user: user, project: project} do
      unsaved_job_id = Ecto.UUID.generate()
      workflow = insert(:workflow, project: project)

      # workflow_template session — no job in DB, no job_id on session
      session =
        insert(:chat_session,
          user: user,
          session_type: "workflow_template",
          project: project,
          workflow: workflow,
          job_id: nil,
          meta: %{}
        )

      # User message carries unsaved_job data in meta (set by handle_unsaved_job_message)
      {:ok, updated_session} =
        AiAssistant.save_message(
          session,
          %{
            role: :user,
            content: "explain this code",
            user: user,
            meta: %{
              "unsaved_job" => %{
                "id" => unsaved_job_id,
                "name" => "My Unsaved Job",
                "body" => "fn(state => state)",
                "adaptor" => "@openfn/language-common@latest"
              }
            }
          },
          []
        )

      user_message = Enum.find(updated_session.messages, &(&1.role == :user))
      assert user_message.meta["unsaved_job"]["id"] == unsaved_job_id

      # update_session_with_job_context copies meta["unsaved_job"] from the
      # message into session.meta, causing job_chat? to return true
      assert :ok =
               perform_job(MessageProcessor, %{"message_id" => user_message.id})

      reloaded = AiAssistant.get_session!(session.id)
      assistant_message = Enum.find(reloaded.messages, &(&1.role == :assistant))

      # process_job_message runs; maybe_put_unsaved_job_meta tags the assistant
      # reply with the unsaved job id
      assert assistant_message != nil
      assert assistant_message.meta["from_unsaved_job"] == unsaved_job_id
    end

    @tag :capture_log
    test "leaves session unchanged and routes to workflow chat processing when message has no job context",
         %{user: user, project: project} do
      workflow = insert(:workflow, project: project)

      session =
        insert(:chat_session,
          user: user,
          session_type: "workflow_template",
          project: project,
          workflow: workflow,
          job_id: nil,
          meta: %{}
        )

      # Plain workflow message — no job_id, no unsaved_job in meta
      {:ok, updated_session} =
        AiAssistant.save_message(
          session,
          %{role: :user, content: "generate a workflow for me", user: user},
          []
        )

      user_message = Enum.find(updated_session.messages, &(&1.role == :user))
      assert is_nil(user_message.job_id)

      # update_session_with_job_context returns the session unchanged, so
      # job_chat? is false and process_workflow_message runs
      assert :ok =
               perform_job(MessageProcessor, %{"message_id" => user_message.id})

      reloaded = AiAssistant.get_session!(session.id)
      assistant_message = Enum.find(reloaded.messages, &(&1.role == :assistant))

      assert assistant_message != nil
      assert is_nil(assistant_message.job_id)
      refute Map.has_key?(assistant_message.meta || %{}, "from_unsaved_job")
    end
  end
end
