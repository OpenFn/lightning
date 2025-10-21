defmodule Lightning.AiAssistant.MessageProcessorComprehensiveTest do
  use Lightning.DataCase, async: false
  use Mimic

  alias Lightning.AiAssistant
  alias Lightning.AiAssistant.MessageProcessor
  alias Lightning.Repo

  import Lightning.Factories
  import Mox, only: []

  @moduletag :capture_log

  setup_all do
    Mimic.copy(Lightning.ApolloClient.SSEStream)
    Mimic.copy(Lightning.ApolloClient)
    Mimic.copy(Lightning.AiAssistant)
    :ok
  end

  setup do
    Mox.set_mox_global()
    Mimic.set_mimic_global()
    Mox.verify_on_exit!()
    :ok
  end

  setup do
    Mox.stub(Lightning.MockConfig, :apollo, fn
      :timeout -> 30_000
      :endpoint -> "http://localhost:3000"
      :ai_assistant_api_key -> "test_key"
    end)

    :ok
  end

  describe "MessageProcessor worker functions" do
    setup do
      user = insert(:user)
      workflow = insert(:simple_workflow, project: build(:project))
      job = hd(workflow.jobs)

      Oban.Testing.with_testing_mode(:manual, fn ->
        {:ok, session} = AiAssistant.create_session(job, user, "Test message")

        message =
          session.messages
          |> Enum.find(&(&1.role == :user))

        {:ok, user: user, session: session, message: message, job: job}
      end)
    end

    test "processes job message with streaming", %{message: message} do
      # Stub streaming to succeed
      Mimic.stub(Lightning.ApolloClient.SSEStream, :start_stream, fn _url, _payload ->
        {:ok, self()}
      end)

      job = %Oban.Job{args: %{"message_id" => message.id}}
      assert :ok = MessageProcessor.perform(job)
    end

    test "handles streaming fallback on exception", %{message: message, session: session} do
      # Update session meta to include options
      session
      |> Ecto.Changeset.change(meta: %{"message_options" => %{"include_logs" => "false"}})
      |> Repo.update!()

      # Stub streaming to fail
      Mimic.stub(Lightning.ApolloClient.SSEStream, :start_stream, fn _url, _payload ->
        raise "Streaming failed"
      end)

      # Stub the fallback AiAssistant.query
      Mimic.stub(Lightning.AiAssistant, :query, fn _session, _content, _opts ->
        {:ok, session}
      end)

      job = %Oban.Job{args: %{"message_id" => message.id}}
      assert :ok = MessageProcessor.perform(job)
    end

    test "calculates timeout with buffer" do
      job = %Oban.Job{args: %{}}
      timeout = MessageProcessor.timeout(job)

      # Should be at least 33_000 (30_000 + 10%)
      assert timeout >= 33_000
    end

    test "updates message status through lifecycle", %{message: message} do
      # Test status progression
      {:ok, _session, updated_message} =
        MessageProcessor.update_message_status(message, :processing)

      assert updated_message.status == :processing

      {:ok, _session, updated_message} =
        MessageProcessor.update_message_status(updated_message, :success)

      assert updated_message.status == :success
    end

    test "handles error status updates", %{message: message} do
      {:ok, _session, updated_message} =
        MessageProcessor.update_message_status(message, :error)

      assert updated_message.status == :error
    end

    test "handles SSEStream.start_stream error for job message", %{message: message} do
      # Stub streaming to return error
      Mimic.stub(Lightning.ApolloClient.SSEStream, :start_stream, fn _url, _payload ->
        {:error, :connection_failed}
      end)

      job = %Oban.Job{args: %{"message_id" => message.id}}

      # Should catch the raised exception from start_streaming_request
      assert :ok = MessageProcessor.perform(job)
    end

    test "handles failed message processing", %{message: message} do
      # Stub streaming to succeed but return error on query fallback
      Mimic.stub(Lightning.ApolloClient.SSEStream, :start_stream, fn _url, _payload ->
        raise "Streaming failed"
      end)

      # Stub the fallback to return error
      Mimic.stub(Lightning.AiAssistant, :query, fn _session, _content, _opts ->
        {:error, "Processing failed"}
      end)

      job = %Oban.Job{args: %{"message_id" => message.id}}
      assert :ok = MessageProcessor.perform(job)

      # Message should be marked as error
      updated_message = Repo.reload(message)
      assert updated_message.status == :error
    end

    test "logs successful message processing", %{message: message} do
      # Stub streaming to fail, then fallback to succeed
      Mimic.stub(Lightning.ApolloClient.SSEStream, :start_stream, fn _url, _payload ->
        raise "Streaming failed"
      end)

      # Stub the fallback to return success (not :streaming)
      Mimic.stub(Lightning.AiAssistant, :query, fn session, _content, _opts ->
        {:ok, session}
      end)

      job = %Oban.Job{args: %{"message_id" => message.id}}
      assert :ok = MessageProcessor.perform(job)

      # Message should be marked as success
      updated_message = Repo.reload(message)
      assert updated_message.status == :success
    end

    test "logs successful SSE stream start for job message", %{message: message} do
      # Stub streaming to succeed and verify logging happens
      Mimic.stub(Lightning.ApolloClient.SSEStream, :start_stream, fn _url, _payload ->
        {:ok, self()}
      end)

      # Call start_streaming_request directly (it's private but we can test via perform)
      job = %Oban.Job{args: %{"message_id" => message.id}}
      assert :ok = MessageProcessor.perform(job)
    end
  end

  describe "workflow message processing" do
    setup do
      user = insert(:user)
      project = insert(:project)
      workflow = insert(:simple_workflow, project: project)

      Oban.Testing.with_testing_mode(:manual, fn ->
        {:ok, session} =
          AiAssistant.create_workflow_session(
            project,
            workflow,
            user,
            "Generate workflow",
            meta: %{"code" => "workflow: test"}
          )

        message =
          session.messages
          |> Enum.find(&(&1.role == :user))

        {:ok, user: user, session: session, message: message, workflow: workflow}
      end)
    end

    test "processes workflow message with streaming", %{message: message} do
      # Stub streaming to succeed
      Mimic.stub(Lightning.ApolloClient.SSEStream, :start_stream, fn _url, _payload ->
        {:ok, self()}
      end)

      job = %Oban.Job{args: %{"message_id" => message.id}}
      assert :ok = MessageProcessor.perform(job)
    end

    test "handles SSEStream.start_stream error for workflow message", %{message: message} do
      # Stub streaming to return error
      Mimic.stub(Lightning.ApolloClient.SSEStream, :start_stream, fn _url, _payload ->
        {:error, :connection_failed}
      end)

      job = %Oban.Job{args: %{"message_id" => message.id}}

      # Should catch the raised exception from start_workflow_streaming_request
      assert :ok = MessageProcessor.perform(job)
    end

    test "falls back to query_workflow on streaming failure", %{message: message, session: session} do
      # Stub streaming to fail
      Mimic.stub(Lightning.ApolloClient.SSEStream, :start_stream, fn _url, _payload ->
        raise "Streaming failed"
      end)

      # Stub the fallback query_workflow
      Mimic.stub(Lightning.AiAssistant, :query_workflow, fn _session, _content, _opts ->
        {:ok, session}
      end)

      job = %Oban.Job{args: %{"message_id" => message.id}}
      assert :ok = MessageProcessor.perform(job)
    end

    test "uses code from previous assistant message when not in message", %{
      user: user,
      workflow: workflow
    } do
      Oban.Testing.with_testing_mode(:manual, fn ->
        {:ok, session} =
          AiAssistant.create_workflow_session(
            workflow.project,
            workflow,
            user,
            "First message",
            meta: %{"code" => "workflow: test"}
          )

        # Add an assistant response with code
        assistant_msg =
          insert(:chat_message,
            chat_session: session,
            role: :assistant,
            content: "Here's a workflow",
            code: "workflow:\n  jobs:\n    - id: job1"
          )

        # Add a new user message without code
        message =
          insert(:chat_message,
            chat_session: session,
            role: :user,
            content: "Update the workflow"
          )

        # Stub streaming to succeed
        Mimic.stub(Lightning.ApolloClient.SSEStream, :start_stream, fn _url, payload ->
          # Verify it used the code from the previous assistant message
          assert payload["existing_yaml"] == assistant_msg.code
          {:ok, self()}
        end)

        job = %Oban.Job{args: %{"message_id" => message.id}}
        assert :ok = MessageProcessor.perform(job)
      end)
    end

    test "logs successful SSE stream start for workflow message", %{message: message} do
      # Stub streaming to succeed
      Mimic.stub(Lightning.ApolloClient.SSEStream, :start_stream, fn _url, _payload ->
        {:ok, self()}
      end)

      job = %Oban.Job{args: %{"message_id" => message.id}}
      assert :ok = MessageProcessor.perform(job)
    end
  end

  describe "telemetry event handlers" do
    setup do
      user = insert(:user)
      workflow = insert(:simple_workflow, project: build(:project))
      job = hd(workflow.jobs)

      Oban.Testing.with_testing_mode(:manual, fn ->
        {:ok, session} = AiAssistant.create_session(job, user, "Test message")

        message =
          session.messages
          |> Enum.find(&(&1.role == :user))

        {:ok, session: session, message: message}
      end)
    end

    test "handle_ai_assistant_exception logs error", %{message: message} do
      measure = %{duration: 1_000_000, memory: 1000, reductions: 100}

      job = %Oban.Job{
        id: 123,
        worker: "Lightning.AiAssistant.MessageProcessor",
        queue: :ai_assistant,
        args: %{"message_id" => message.id}
      }

      meta = %{
        error: %RuntimeError{message: "test error"},
        stacktrace: [],
        job: job
      }

      # Should not crash and should update message to error
      MessageProcessor.handle_ai_assistant_exception(measure, meta)

      # Verify message was updated to error
      updated_message = Repo.reload(message)
      assert updated_message.status == :error
    end

    test "handle_ai_assistant_stop with non-success state", %{message: message} do
      measure = %{duration: 1_000_000, memory: 1000, reductions: 100}

      job = %Oban.Job{
        id: 123,
        worker: "Lightning.AiAssistant.MessageProcessor",
        queue: :ai_assistant,
        args: %{"message_id" => message.id}
      }

      meta = %{
        state: :cancelled,
        job: job
      }

      MessageProcessor.handle_ai_assistant_stop(measure, meta)

      # Verify message was updated to error
      updated_message = Repo.reload(message)
      assert updated_message.status == :error
    end

    test "handle_ai_assistant_stop with success state", %{message: message} do
      measure = %{duration: 1_000_000, memory: 1000, reductions: 100}

      job = %Oban.Job{
        id: 123,
        worker: "Lightning.AiAssistant.MessageProcessor",
        queue: :ai_assistant,
        args: %{"message_id" => message.id}
      }

      meta = %{
        state: :success,
        job: job
      }

      # Success state should be ignored
      assert :ok = MessageProcessor.handle_ai_assistant_stop(measure, meta)
    end

    test "handle_ai_assistant_exception skips message already in final state", %{
      message: message
    } do
      # Update message to success (final state)
      {:ok, _session, updated_message} =
        MessageProcessor.update_message_status(message, :success)

      measure = %{duration: 1_000_000, memory: 1000, reductions: 100}

      job = %Oban.Job{
        id: 123,
        worker: "Lightning.AiAssistant.MessageProcessor",
        queue: :ai_assistant,
        args: %{"message_id" => updated_message.id}
      }

      meta = %{
        error: %RuntimeError{message: "test error"},
        stacktrace: [],
        job: job
      }

      # Should not update message since it's already in success state
      MessageProcessor.handle_ai_assistant_exception(measure, meta)

      # Verify message is still in success state
      final_message = Repo.reload(updated_message)
      assert final_message.status == :success
    end

    test "handle_ai_assistant_stop with message already in final state", %{
      message: message
    } do
      # Update message to success (final state)
      {:ok, _session, updated_message} =
        MessageProcessor.update_message_status(message, :success)

      measure = %{duration: 1_000_000, memory: 1000, reductions: 100}

      job = %Oban.Job{
        id: 123,
        worker: "Lightning.AiAssistant.MessageProcessor",
        queue: :ai_assistant,
        args: %{"message_id" => updated_message.id}
      }

      meta = %{
        state: :cancelled,
        job: job
      }

      # Should not update message since it's already in success state
      MessageProcessor.handle_ai_assistant_stop(measure, meta)

      # Verify message is still in success state
      final_message = Repo.reload(updated_message)
      assert final_message.status == :success
    end
  end
end
