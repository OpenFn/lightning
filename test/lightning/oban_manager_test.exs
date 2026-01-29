defmodule Lightning.ObanManagerTest do
  use Lightning.DataCase, async: false

  import ExUnit.CaptureLog
  import Mox

  alias Lightning.AiAssistant
  alias Lightning.AiAssistant.ChatMessage
  alias Lightning.ObanManager
  alias Lightning.Repo

  setup :set_mox_from_context
  setup :verify_on_exit!

  setup do
    Mox.stub(Lightning.MockConfig, :sentry, fn -> Lightning.MockSentry end)
    :ok
  end

  defp ai_setup(_) do
    Oban.Testing.with_testing_mode(:manual, fn ->
      user = insert(:user)
      job = insert(:job)

      {:ok, session} =
        AiAssistant.create_session(job, user, "Test message", meta: %{})

      message = hd(session.messages)

      oban_job = %{
        id: 123,
        queue: "ai_assistant",
        worker: "Lightning.AiAssistant.MessageProcessor",
        args: %{"message_id" => message.id, "session_id" => session.id}
      }

      %{
        session: session,
        message: message,
        oban_job: oban_job,
        user: user,
        job: job
      }
    end)
  end

  describe "handle_event/4 for AI Assistant queue" do
    setup :ai_setup

    test "handles timeout exception for pending message", %{
      message: message,
      oban_job: oban_job
    } do
      {:ok, _} = Repo.update(Ecto.Changeset.change(message, %{status: :pending}))

      error = %Oban.TimeoutError{
        message:
          "Lightning.AiAssistant.MessageProcessor timed out after 31000ms",
        reason: :timeout
      }

      meta = %{job: oban_job, error: error, stacktrace: []}
      measure = %{duration: 31_000_000_000, memory: 50_000, reductions: 400_000}

      expect(Lightning.MockSentry, :capture_message, fn msg, opts ->
        assert msg ==
                 "AI Assistant Timeout: Lightning.AiAssistant.MessageProcessor"

        assert opts[:level] == :warning
        assert opts[:tags][:type] == "ai_timeout"
        :ok
      end)

      logs =
        capture_log(fn ->
          ObanManager.handle_event(
            [:oban, :job, :exception],
            measure,
            meta,
            self()
          )
        end)

      assert logs =~ "AI Assistant exception:"
      assert logs =~ "Type: Timeout"

      updated_message = Repo.get!(ChatMessage, message.id)
      assert updated_message.status == :error
      assert updated_message.processing_completed_at != nil
    end

    test "handles generic exception for processing message", %{
      message: message,
      oban_job: oban_job
    } do
      {:ok, _} =
        Repo.update(Ecto.Changeset.change(message, %{status: :processing}))

      error = %RuntimeError{message: "Something went wrong"}

      meta = %{
        job: oban_job,
        error: error,
        stacktrace: [
          {Lightning.SomeModule, :some_function, 2,
           [file: "lib/some_module.ex", line: 42]}
        ]
      }

      measure = %{duration: 5_000_000_000, memory: 30_000, reductions: 200_000}

      expect(Lightning.MockSentry, :capture_exception, fn error, opts ->
        assert %RuntimeError{} = error
        assert opts[:stacktrace] == meta.stacktrace
        assert opts[:tags][:type] == "ai_error"
        :ok
      end)

      logs =
        capture_log(fn ->
          ObanManager.handle_event(
            [:oban, :job, :exception],
            measure,
            meta,
            self()
          )
        end)

      assert logs =~ "AI Assistant exception:"
      assert logs =~ "Type: Error"

      updated_message = Repo.get!(ChatMessage, message.id)
      assert updated_message.status == :error
    end

    test "skips update for already completed message", %{
      message: message,
      oban_job: oban_job
    } do
      {:ok, _} = Repo.update(Ecto.Changeset.change(message, %{status: :success}))

      error = %Oban.TimeoutError{reason: :timeout}
      meta = %{job: oban_job, error: error, stacktrace: []}
      measure = %{duration: 1_000, memory: 1_000, reductions: 1_000}

      expect(Lightning.MockSentry, :capture_message, fn _, _ -> :ok end)

      capture_log(fn ->
        ObanManager.handle_event(
          [:oban, :job, :exception],
          measure,
          meta,
          self()
        )
      end)

      updated_message = Repo.get!(ChatMessage, message.id)
      assert updated_message.status == :success
    end
  end

  describe "handle_event/4 for other queues" do
    test "handles timeout for non-AI queue" do
      oban_job = %{
        id: 456,
        queue: "background",
        worker: "SomeOtherWorker",
        args: %{}
      }

      error = %Oban.TimeoutError{reason: :timeout}
      meta = %{job: oban_job, error: error, stacktrace: []}
      measure = %{duration: 10_000, memory: 5_000, reductions: 10_000}

      expect(Lightning.MockSentry, :capture_message, fn msg, opts ->
        assert msg == "Processor Timeout"
        assert opts[:level] == :warning
        assert opts[:tags][:type] == "timeout"
        :ok
      end)

      logs =
        capture_log([level: :debug], fn ->
          ObanManager.handle_event(
            [:oban, :job, :exception],
            measure,
            meta,
            self()
          )
        end)

      assert logs =~ "Oban exception:"
      assert logs =~ "TimeoutError"
    end

    test "handles generic exception for non-AI queue" do
      oban_job = %{
        id: 789,
        queue: "workflow_failures",
        worker: "WorkflowWorker",
        args: %{"workflow_id" => "123"}
      }

      error = %ArgumentError{message: "invalid argument"}

      meta = %{
        job: oban_job,
        error: error,
        stacktrace: [{Module, :function, 1, [file: "lib/module.ex", line: 10]}]
      }

      measure = %{duration: 500, memory: 1_000, reductions: 500}

      expect(Lightning.MockSentry, :capture_exception, fn error, opts ->
        assert %ArgumentError{} = error
        assert opts[:stacktrace] == meta.stacktrace
        assert opts[:tags][:type] == "oban"
        :ok
      end)

      logs =
        capture_log([level: :debug], fn ->
          ObanManager.handle_event(
            [:oban, :job, :exception],
            measure,
            meta,
            self()
          )
        end)

      assert logs =~ "Oban exception:"
      assert logs =~ "ArgumentError"
      refute logs =~ "AI Assistant exception:"
    end
  end

  describe "broadcasting" do
    setup :ai_setup

    test "broadcasts error status update", %{
      message: message,
      oban_job: oban_job
    } do
      Lightning.subscribe("ai_session:#{message.chat_session_id}")

      {:ok, _} = Repo.update(Ecto.Changeset.change(message, %{status: :pending}))

      error = %Oban.TimeoutError{reason: :timeout}
      meta = %{job: oban_job, error: error, stacktrace: []}
      measure = %{duration: 1_000, memory: 1_000, reductions: 1_000}

      expect(Lightning.MockSentry, :capture_message, fn _, _ -> :ok end)

      logs =
        capture_log([level: :warning], fn ->
          ObanManager.handle_event(
            [:oban, :job, :exception],
            measure,
            meta,
            self()
          )
        end)

      assert logs =~ "AI Assistant exception:"

      assert_receive {:ai_assistant, :message_status_changed,
                      %{status: {:error, _}, session_id: _}}

      updated_message = Repo.get!(ChatMessage, message.id)
      assert updated_message.status == :error
      assert updated_message.processing_completed_at != nil
    end
  end

  describe "handle_event/4 :stop for AI Assistant queue" do
    setup :ai_setup

    test "no-op on success stop", %{message: message, oban_job: oban_job} do
      logs =
        capture_log([level: :warning], fn ->
          ObanManager.handle_event(
            [:oban, :job, :stop],
            %{duration: 1_000, memory: 1_000, reductions: 1_000},
            %{job: oban_job, state: :success},
            self()
          )
        end)

      refute logs =~ "AI Assistant stop (non-success):"

      reloaded = Repo.get!(ChatMessage, message.id)
      assert reloaded.status == message.status
    end

    test "marks message error on non-success stop and broadcasts", %{
      message: message,
      oban_job: oban_job
    } do
      Lightning.subscribe("ai_session:#{message.chat_session_id}")

      {:ok, _} =
        Repo.update(Ecto.Changeset.change(message, %{status: :processing}))

      expect(Lightning.MockSentry, :capture_message, fn msg, opts ->
        assert msg ==
                 "AI Assistant Stop (discarded): Lightning.AiAssistant.MessageProcessor"

        assert opts[:level] == :warning
        assert opts[:tags][:type] == "ai_stop"
        assert opts[:tags][:queue] == "ai_assistant"
        assert opts[:tags][:worker] == "Lightning.AiAssistant.MessageProcessor"
        :ok
      end)

      logs =
        capture_log([level: :warning], fn ->
          ObanManager.handle_event(
            [:oban, :job, :stop],
            %{duration: 2_000, memory: 2_000, reductions: 2_000},
            %{job: oban_job, state: :discarded},
            self()
          )
        end)

      assert logs =~ "AI Assistant stop (non-success):"

      assert_receive {:ai_assistant, :message_status_changed,
                      %{status: {:error, _}, session_id: _}}

      updated = Repo.get!(ChatMessage, message.id)
      assert updated.status == :error
      assert updated.processing_completed_at != nil
    end

    test "ignores stop for non-AI queues" do
      meta = %{
        job: %{id: 42, queue: "background", worker: "SomeOther", args: %{}},
        state: :discarded
      }

      logs =
        capture_log([level: :warning], fn ->
          assert :ok =
                   ObanManager.handle_event(
                     [:oban, :job, :stop],
                     %{duration: 1},
                     meta,
                     self()
                   )
        end)

      refute logs =~ "AI Assistant stop"
    end
  end
end
