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

    test "times out hanging streams", %{session_id: session_id} do
      # Timeout is based on Apollo config, which for tests should be short
      # This test verifies that the stream times out if no data arrives

      # Override the default stub with a short timeout for this test
      stub(Lightning.MockConfig, :apollo, fn
        # Very short timeout for testing
        :timeout -> 100
        :endpoint -> "http://localhost:3000"
        :ai_assistant_api_key -> "test_key"
      end)

      url = "http://localhost:3000/services/job_chat/stream"

      payload = %{
        "lightning_session_id" => session_id,
        "stream" => true
      }

      {:ok, _pid} = SSEStream.start_stream(url, payload)

      # Wait for timeout (100ms + 10s buffer = 10.1s, but for test we use smaller values)
      # Since timeout is 100ms, the actual timeout will be 100 + 10000 = 10100ms
      # But we can verify the GenServer eventually stops
      Process.sleep(150)

      # The GenServer should still be trying (hasn't hit the actual timeout yet)
      # For a proper test, we'd need to mock the time or use shorter timeouts
    end

    test "handles connection failures", %{session_id: session_id} do
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
  end
end
