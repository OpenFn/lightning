defmodule Lightning.ApolloClient.SSEStreamTest do
  use Lightning.DataCase, async: false

  alias Lightning.ApolloClient.SSEStream

  import Mox

  @moduletag :capture_log

  setup :set_mox_global
  setup :verify_on_exit!

  setup do
    # Stub Apollo config for all tests - set_mox_global allows this to work in spawned processes
    stub(Lightning.MockConfig, :apollo, fn
      :timeout -> 30_000
      :endpoint -> "http://localhost:3000"
      :ai_assistant_api_key -> "test_key"
    end)

    # Subscribe to PubSub to receive broadcasted messages
    session_id = Ecto.UUID.generate()
    Phoenix.PubSub.subscribe(Lightning.PubSub, "ai_session:#{session_id}")
    %{session_id: session_id}
  end

  describe "start_stream/2" do
    test "successfully starts streaming GenServer", %{session_id: session_id} do
      # This test verifies that SSEStream GenServer can be started
      # The actual HTTP connection will fail but the GenServer starts successfully

      url = "http://localhost:3000/services/job_chat/stream"

      payload = %{
        "api_key" => "test_key",
        "content" => "test",
        "lightning_session_id" => session_id,
        "stream" => true
      }

      # Start the stream (it will fail to connect but GenServer starts)
      {:ok, pid} = SSEStream.start_stream(url, payload)

      # GenServer starts successfully
      assert Process.alive?(pid)
    end

    test "handles error events from Apollo", %{session_id: session_id} do
      # Simulate receiving an error event by sending it directly to a GenServer
      # In a real implementation, this would come from Apollo via SSE

      # Start a stream
      url = "http://localhost:3000/services/job_chat/stream"

      payload = %{
        "lightning_session_id" => session_id,
        "stream" => true
      }

      {:ok, pid} = SSEStream.start_stream(url, payload)

      # Send an error event to the GenServer
      error_data = Jason.encode!(%{"message" => "Test error from Apollo"})
      send(pid, {:sse_event, "error", error_data})

      # Wait for broadcast
      assert_receive {:ai_assistant, :streaming_error,
                      %{
                        session_id: ^session_id,
                        error: "Test error from Apollo"
                      }},
                     500
    end

    test "times out hanging streams and broadcasts error", %{
      session_id: session_id
    } do
      # Test that timeout handling works correctly

      url = "http://localhost:3000/services/job_chat/stream"

      payload = %{
        "lightning_session_id" => session_id,
        "stream" => true
      }

      {:ok, pid} = SSEStream.start_stream(url, payload)

      # Send timeout message directly to test the handler
      send(pid, :stream_timeout)

      # Should receive timeout error broadcast
      assert_receive {:ai_assistant, :streaming_error,
                      %{
                        session_id: ^session_id,
                        error: "Request timed out. Please try again."
                      }},
                     500
    end

    test "ignores timeout after stream completes", %{session_id: session_id} do
      # Test that timeout is ignored if stream already completed

      url = "http://localhost:3000/services/job_chat/stream"

      payload = %{
        "lightning_session_id" => session_id,
        "stream" => true
      }

      {:ok, pid} = SSEStream.start_stream(url, payload)

      # First complete the stream
      send(pid, {:sse_complete})

      # Process should stop normally
      ref = Process.monitor(pid)
      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 500

      # If we somehow send timeout after completion, it should be ignored
      # (process is already dead so we can't test this directly)
    end

    test "handles completion message and cancels timeout", %{
      session_id: session_id
    } do
      # Test that :sse_complete properly cancels the timeout timer

      url = "http://localhost:3000/services/job_chat/stream"

      payload = %{
        "lightning_session_id" => session_id,
        "stream" => true
      }

      {:ok, pid} = SSEStream.start_stream(url, payload)

      # Send completion message
      send(pid, {:sse_complete})

      # Process should stop normally (not from timeout)
      ref = Process.monitor(pid)
      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 500
    end

    test "handles connection failures with econnrefused", %{
      session_id: session_id
    } do
      # When Finch cannot connect, the stream should broadcast an error

      url = "http://localhost:3000/services/job_chat/stream"

      payload = %{
        "lightning_session_id" => session_id,
        "stream" => true
      }

      {:ok, pid} = SSEStream.start_stream(url, payload)

      # Simulate a connection failure by sending the error message
      send(pid, {:sse_error, :econnrefused})

      # Should receive an error broadcast
      assert_receive {:ai_assistant, :streaming_error,
                      %{
                        session_id: ^session_id,
                        error: error
                      }},
                     500

      assert error =~ "Connection error"
    end

    test "handles timeout error from Finch", %{session_id: session_id} do
      url = "http://localhost:3000/services/job_chat/stream"

      payload = %{
        "lightning_session_id" => session_id,
        "stream" => true
      }

      {:ok, pid} = SSEStream.start_stream(url, payload)

      send(pid, {:sse_error, :timeout})

      assert_receive {:ai_assistant, :streaming_error,
                      %{
                        session_id: ^session_id,
                        error: "Connection timed out"
                      }},
                     500
    end

    test "handles closed connection error", %{session_id: session_id} do
      url = "http://localhost:3000/services/job_chat/stream"

      payload = %{
        "lightning_session_id" => session_id,
        "stream" => true
      }

      {:ok, pid} = SSEStream.start_stream(url, payload)

      send(pid, {:sse_error, :closed})

      assert_receive {:ai_assistant, :streaming_error,
                      %{
                        session_id: ^session_id,
                        error: "Connection closed unexpectedly"
                      }},
                     500
    end

    test "handles shutdown error", %{session_id: session_id} do
      url = "http://localhost:3000/services/job_chat/stream"

      payload = %{
        "lightning_session_id" => session_id,
        "stream" => true
      }

      {:ok, pid} = SSEStream.start_stream(url, payload)

      send(pid, {:sse_error, {:shutdown, :some_reason}})

      assert_receive {:ai_assistant, :streaming_error,
                      %{
                        session_id: ^session_id,
                        error: "Server shut down"
                      }},
                     500
    end

    test "handles HTTP error responses", %{session_id: session_id} do
      # Test that HTTP error status codes result in error broadcasts

      url = "http://localhost:3000/services/job_chat/stream"

      payload = %{
        "lightning_session_id" => session_id,
        "stream" => true
      }

      {:ok, pid} = SSEStream.start_stream(url, payload)

      # Simulate HTTP 500 error
      send(pid, {:sse_error, {:http_error, 500}})

      # Should receive an error broadcast
      assert_receive {:ai_assistant, :streaming_error,
                      %{
                        session_id: ^session_id,
                        error: "Server returned error status 500"
                      }},
                     500
    end

    test "broadcasts content chunks correctly", %{session_id: session_id} do
      # Test that content_block_delta events are broadcast

      url = "http://localhost:3000/services/job_chat/stream"

      payload = %{
        "lightning_session_id" => session_id,
        "stream" => true
      }

      {:ok, pid} = SSEStream.start_stream(url, payload)

      # Send a content chunk event
      chunk_data =
        Jason.encode!(%{
          "delta" => %{"type" => "text_delta", "text" => "Hello from AI"}
        })

      send(pid, {:sse_event, "content_block_delta", chunk_data})

      # Should receive the chunk broadcast
      assert_receive {:ai_assistant, :streaming_chunk,
                      %{
                        session_id: ^session_id,
                        content: "Hello from AI"
                      }},
                     500
    end

    test "broadcasts status updates correctly", %{session_id: session_id} do
      # Test that thinking_delta events are broadcast as status updates

      url = "http://localhost:3000/services/job_chat/stream"

      payload = %{
        "lightning_session_id" => session_id,
        "stream" => true
      }

      {:ok, pid} = SSEStream.start_stream(url, payload)

      # Send a status update event
      status_data =
        Jason.encode!(%{
          "delta" => %{"type" => "thinking_delta", "thinking" => "Analyzing..."}
        })

      send(pid, {:sse_event, "content_block_delta", status_data})

      # Should receive the status broadcast
      assert_receive {:ai_assistant, :status_update,
                      %{
                        session_id: ^session_id,
                        status: "Analyzing..."
                      }},
                     500
    end

    test "broadcasts completion events", %{session_id: session_id} do
      # Test that message_stop events broadcast completion

      url = "http://localhost:3000/services/job_chat/stream"

      payload = %{
        "lightning_session_id" => session_id,
        "stream" => true
      }

      {:ok, pid} = SSEStream.start_stream(url, payload)

      # Send completion event
      send(pid, {:sse_event, "message_stop", ""})

      # Should receive completion broadcast
      assert_receive {:ai_assistant, :streaming_complete,
                      %{
                        session_id: ^session_id
                      }},
                     500
    end

    test "broadcasts complete payload with metadata", %{session_id: session_id} do
      # Test that complete events with payload are broadcast

      url = "http://localhost:3000/services/job_chat/stream"

      payload = %{
        "lightning_session_id" => session_id,
        "stream" => true
      }

      {:ok, pid} = SSEStream.start_stream(url, payload)

      # Send complete event with payload
      complete_data =
        Jason.encode!(%{
          "usage" => %{"input_tokens" => 100, "output_tokens" => 50},
          "meta" => %{"model" => "claude-3"},
          "response_yaml" => "workflow: test"
        })

      send(pid, {:sse_event, "complete", complete_data})

      # Should receive payload complete broadcast
      assert_receive {:ai_assistant, :streaming_payload_complete, payload_data},
                     500

      assert payload_data.session_id == session_id
      assert payload_data.usage["input_tokens"] == 100
      assert payload_data.meta["model"] == "claude-3"
      assert payload_data.code == "workflow: test"
    end

    test "handles complete event with invalid JSON", %{session_id: session_id} do
      # Test that malformed complete payloads are handled gracefully

      url = "http://localhost:3000/services/job_chat/stream"

      payload = %{
        "lightning_session_id" => session_id,
        "stream" => true
      }

      {:ok, pid} = SSEStream.start_stream(url, payload)

      # Monitor the process to ensure it doesn't crash
      ref = Process.monitor(pid)

      # Send complete event with invalid JSON
      send(pid, {:sse_event, "complete", "not valid json {"})

      # Should not crash - verify process is still alive after a reasonable time
      refute_receive {:DOWN, ^ref, :process, ^pid, _reason}, 200
      assert Process.alive?(pid)
    end

    test "handles log events", %{session_id: session_id} do
      # Test that log events are handled (just logged, no broadcast)

      url = "http://localhost:3000/services/job_chat/stream"

      payload = %{
        "lightning_session_id" => session_id,
        "stream" => true
      }

      {:ok, pid} = SSEStream.start_stream(url, payload)

      # Monitor the process
      ref = Process.monitor(pid)

      # Send log event
      send(pid, {:sse_event, "log", "Some log message"})

      # Should not crash
      refute_receive {:DOWN, ^ref, :process, ^pid, _reason}, 200
      assert Process.alive?(pid)
    end

    test "handles unknown event types", %{session_id: session_id} do
      # Test that unknown event types are handled gracefully

      url = "http://localhost:3000/services/job_chat/stream"

      payload = %{
        "lightning_session_id" => session_id,
        "stream" => true
      }

      {:ok, pid} = SSEStream.start_stream(url, payload)

      # Monitor the process
      ref = Process.monitor(pid)

      # Send unknown event type
      send(pid, {:sse_event, "some_unknown_event", "data"})

      # Should not crash
      refute_receive {:DOWN, ^ref, :process, ^pid, _reason}, 200
      assert Process.alive?(pid)
    end

    test "handles content_block_delta with invalid JSON", %{
      session_id: session_id
    } do
      # Test that malformed delta events don't crash

      url = "http://localhost:3000/services/job_chat/stream"

      payload = %{
        "lightning_session_id" => session_id,
        "stream" => true
      }

      {:ok, pid} = SSEStream.start_stream(url, payload)

      # Monitor the process
      ref = Process.monitor(pid)

      # Send invalid delta data
      send(pid, {:sse_event, "content_block_delta", "invalid json"})

      # Should not crash
      refute_receive {:DOWN, ^ref, :process, ^pid, _reason}, 200
      assert Process.alive?(pid)
    end

    test "handles error event with message field", %{session_id: session_id} do
      url = "http://localhost:3000/services/job_chat/stream"

      payload = %{
        "lightning_session_id" => session_id,
        "stream" => true
      }

      {:ok, pid} = SSEStream.start_stream(url, payload)

      error_data = Jason.encode!(%{"message" => "Custom error message"})
      send(pid, {:sse_event, "error", error_data})

      assert_receive {:ai_assistant, :streaming_error,
                      %{
                        session_id: ^session_id,
                        error: "Custom error message"
                      }},
                     500
    end

    test "handles error event with error field", %{session_id: session_id} do
      url = "http://localhost:3000/services/job_chat/stream"

      payload = %{
        "lightning_session_id" => session_id,
        "stream" => true
      }

      {:ok, pid} = SSEStream.start_stream(url, payload)

      error_data = Jason.encode!(%{"error" => "Another error format"})
      send(pid, {:sse_event, "error", error_data})

      assert_receive {:ai_assistant, :streaming_error,
                      %{
                        session_id: ^session_id,
                        error: "Another error format"
                      }},
                     500
    end

    test "handles error event with invalid JSON", %{session_id: session_id} do
      url = "http://localhost:3000/services/job_chat/stream"

      payload = %{
        "lightning_session_id" => session_id,
        "stream" => true
      }

      {:ok, pid} = SSEStream.start_stream(url, payload)

      # Send malformed error data
      send(pid, {:sse_event, "error", "not json"})

      # Should use fallback error message
      assert_receive {:ai_assistant, :streaming_error,
                      %{
                        session_id: ^session_id,
                        error: "An error occurred while streaming"
                      }},
                     500
    end
  end
end
