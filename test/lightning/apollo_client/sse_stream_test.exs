defmodule Lightning.ApolloClient.SSEStreamTest do
  use Lightning.DataCase, async: false
  use Mimic

  alias Lightning.ApolloClient.SSEStream

  import Mox, only: []

  @moduletag :capture_log

  setup do
    Mox.set_mox_global()
    Mimic.set_mimic_global()
    # Verify Mox expectations on exit
    Mox.verify_on_exit!()
    :ok
  end

  setup do
    # Stub Apollo config for all tests - set_mox_global allows this to work in spawned processes
    # Use Mox.stub explicitly since both Mox and Mimic export stub/3
    Mox.stub(Lightning.MockConfig, :apollo, fn
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

    test "handles successful streaming with SSE data chunks", %{
      session_id: session_id
    } do
      # Test the full successful streaming path with properly formatted SSE chunks

      # Stub Finch to simulate successful streaming with SSE chunks
      Mimic.stub(Finch, :stream, fn _request, _finch_name, acc, fun ->
        # Simulate status callback
        acc = fun.({:status, 200}, acc)

        # Simulate headers callback
        acc = fun.({:headers, [{"content-type", "text/event-stream"}]}, acc)

        # Simulate SSE data chunks
        chunk1 =
          "event: content_block_delta\ndata: {\"delta\":{\"type\":\"text_delta\",\"text\":\"Hello\"}}\n\n"

        acc = fun.({:data, chunk1}, acc)

        chunk2 = "event: message_stop\ndata: {}\n\n"
        acc = fun.({:data, chunk2}, acc)

        {:ok, acc}
      end)

      url = "http://localhost:3000/services/job_chat/stream"

      payload = %{
        "lightning_session_id" => session_id,
        "stream" => true
      }

      {:ok, _pid} = SSEStream.start_stream(url, payload)

      # Should receive the text chunk
      assert_receive {:ai_assistant, :streaming_chunk,
                      %{content: "Hello", session_id: ^session_id}},
                     1000

      # Should receive completion
      assert_receive {:ai_assistant, :streaming_complete,
                      %{session_id: ^session_id}},
                     1000
    end

    test "handles streaming with thinking_delta status updates", %{
      session_id: session_id
    } do
      # Test status update streaming
      Mimic.stub(Finch, :stream, fn _request, _finch_name, acc, fun ->
        acc = fun.({:status, 200}, acc)
        acc = fun.({:headers, []}, acc)

        chunk =
          "event: content_block_delta\ndata: {\"delta\":{\"type\":\"thinking_delta\",\"thinking\":\"Analyzing...\"}}\n\n"

        acc = fun.({:data, chunk}, acc)

        {:ok, acc}
      end)

      url = "http://localhost:3000/services/job_chat/stream"
      payload = %{"lightning_session_id" => session_id, "stream" => true}

      {:ok, _pid} = SSEStream.start_stream(url, payload)

      # Should receive status update
      assert_receive {:ai_assistant, :status_update,
                      %{status: "Analyzing...", session_id: ^session_id}},
                     1000
    end

    test "handles HTTP 4xx/5xx error during streaming", %{session_id: session_id} do
      # Test handling of HTTP error status codes during streaming
      Mimic.stub(Finch, :stream, fn _request, _finch_name, acc, fun ->
        # Simulate 500 status
        acc = fun.({:status, 500}, acc)

        {:ok, acc}
      end)

      url = "http://localhost:3000/services/job_chat/stream"
      payload = %{"lightning_session_id" => session_id, "stream" => true}

      {:ok, _pid} = SSEStream.start_stream(url, payload)

      # Should receive error about HTTP 500
      assert_receive {:ai_assistant, :streaming_error,
                      %{session_id: ^session_id, error: error}},
                     1000

      assert error =~ "500"
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

    @tag timeout: 5000
    test "times out hanging streams and broadcasts error", %{
      session_id: session_id
    } do
      # Test timeout handling by stubbing Finch to hang
      # This prevents connection errors from interfering with the timeout test

      # Trap exits so we don't crash when the GenServer stops with :timeout
      Process.flag(:trap_exit, true)

      # Stub Finch to block indefinitely, simulating a hanging request
      Mimic.stub(Finch, :stream, fn _request, _finch_name, acc, _fun ->
        # Just block forever (or until killed)
        Process.sleep(:infinity)
        {:ok, Map.put(acc, :status, 200)}
      end)

      url = "http://localhost:3000/services/job_chat/stream"

      payload = %{
        "lightning_session_id" => session_id,
        "stream" => true
      }

      {:ok, pid} = SSEStream.start_stream(url, payload)

      # Give the spawned Finch process time to start
      Process.sleep(50)

      # Send timeout message to simulate stream timeout
      send(pid, :stream_timeout)

      # Should receive timeout error broadcast
      assert_receive {:ai_assistant, :streaming_error,
                      %{
                        session_id: ^session_id,
                        error: "Request timed out. Please try again."
                      }},
                     1000
    end

    test "ignores timeout after stream completes", %{session_id: session_id} do
      # Test that timeout is ignored if stream already completed
      # Note: Stream will fail with connection error, simulating completion

      url = "http://localhost:3000/services/job_chat/stream"

      payload = %{
        "lightning_session_id" => session_id,
        "stream" => true
      }

      {:ok, pid} = SSEStream.start_stream(url, payload)

      # Monitor BEFORE sending completion to catch the shutdown
      ref = Process.monitor(pid)

      # Send completion message - this will complete the stream
      send(pid, {:sse_complete})

      # Process should stop normally
      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 1000

      # If we send timeout after completion, process is already dead so it's ignored
    end

    test "handles completion message and cancels timeout", %{
      session_id: session_id
    } do
      # Test that :sse_complete properly cancels the timeout timer
      # Note: Stream will attempt connection but we complete it before that matters

      url = "http://localhost:3000/services/job_chat/stream"

      payload = %{
        "lightning_session_id" => session_id,
        "stream" => true
      }

      {:ok, pid} = SSEStream.start_stream(url, payload)

      # Monitor BEFORE sending completion to catch the shutdown
      ref = Process.monitor(pid)

      # Send completion message
      send(pid, {:sse_complete})

      # Process should stop normally (not from timeout)
      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 1000
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

      # Send complete event with invalid JSON
      send(pid, {:sse_event, "complete", "not valid json {"})

      # Give it a moment to process - should not crash from invalid JSON itself
      # (though it may eventually stop due to connection error)
      Process.sleep(50)
    end

    test "handles log events", %{session_id: session_id} do
      # Test that log events are handled (just logged, no broadcast)

      url = "http://localhost:3000/services/job_chat/stream"

      payload = %{
        "lightning_session_id" => session_id,
        "stream" => true
      }

      {:ok, pid} = SSEStream.start_stream(url, payload)

      # Send log event
      send(pid, {:sse_event, "log", "Some log message"})

      # Give it a moment to process - should not crash from the log event itself
      # (though it may eventually stop due to connection error)
      Process.sleep(50)
    end

    test "handles unknown event types", %{session_id: session_id} do
      # Test that unknown event types are handled gracefully

      url = "http://localhost:3000/services/job_chat/stream"

      payload = %{
        "lightning_session_id" => session_id,
        "stream" => true
      }

      {:ok, pid} = SSEStream.start_stream(url, payload)

      # Send unknown event type
      send(pid, {:sse_event, "some_unknown_event", "data"})

      # Give it a moment to process - should not crash from unknown event itself
      # (though it may eventually stop due to connection error)
      Process.sleep(50)
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

      # Send invalid delta data
      send(pid, {:sse_event, "content_block_delta", "invalid json"})

      # Give it a moment to process - should not crash from invalid JSON itself
      # (though it may eventually stop due to connection error)
      Process.sleep(50)
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
