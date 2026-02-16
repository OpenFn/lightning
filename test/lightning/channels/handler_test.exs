defmodule Lightning.Channels.HandlerTest do
  use Lightning.DataCase, async: true

  alias Lightning.Channels.Handler
  alias Lightning.Channels.{ChannelRequest, ChannelEvent}

  import Lightning.Factories

  setup do
    channel = insert(:channel)

    snapshot =
      insert(:channel_snapshot,
        channel: channel,
        lock_version: channel.lock_version
      )

    initial_state = %{
      channel: channel,
      snapshot: snapshot,
      started_at: DateTime.utc_now(),
      request_path: "/test/path",
      client_identity: "127.0.0.1"
    }

    Lightning.subscribe("channels:#{channel.id}")

    %{channel: channel, snapshot: snapshot, state: initial_state}
  end

  describe "handle_request_started/2" do
    test "creates a ChannelRequest in pending state", %{state: state} do
      metadata = request_metadata()

      assert {:ok, new_state} = Handler.handle_request_started(metadata, state)

      assert %ChannelRequest{} = new_state.channel_request
      assert new_state.channel_request.state == :pending
      assert new_state.channel_request.request_id == metadata.request_id
      assert new_state.channel_request.channel_id == state.channel.id
      assert new_state.channel_request.channel_snapshot_id == state.snapshot.id
      assert new_state.channel_request.client_identity == "127.0.0.1"

      # Persisted in DB
      assert Repo.get!(ChannelRequest, new_state.channel_request.id)
    end

    test "rejects with 503 on DB failure", %{state: state} do
      bad_state = %{state | channel: %{state.channel | id: Ecto.UUID.generate()}}
      metadata = request_metadata()

      assert {:reject, 503, "Service Unavailable", ^bad_state} =
               Handler.handle_request_started(metadata, bad_state)
    end

    test "redacts sensitive headers in state", %{state: state} do
      metadata =
        request_metadata(
          headers: [
            {"authorization", "Bearer secret-token"},
            {"x-api-key", "my-api-key"},
            {"content-type", "application/json"}
          ]
        )

      assert {:ok, new_state} = Handler.handle_request_started(metadata, state)

      assert [
               {"authorization", "[REDACTED]"},
               {"x-api-key", "[REDACTED]"},
               {"content-type", "application/json"}
             ] = new_state.request_headers
    end

    test "stores request method in state", %{state: state} do
      metadata = request_metadata(method: "POST")

      assert {:ok, new_state} = Handler.handle_request_started(metadata, state)
      assert new_state.request_method == "POST"
    end
  end

  describe "handle_response_started/2" do
    test "captures TTFB and response headers", %{state: state} do
      metadata = %{
        request_id: Ecto.UUID.generate(),
        status: 200,
        headers: [
          {"content-type", "application/json"},
          {"authorization", "Bearer upstream-token"}
        ],
        content_type: "application/json",
        time_to_first_byte_us: 15_000
      }

      assert {:ok, new_state} =
               Handler.handle_response_started(metadata, state)

      assert new_state.ttfb_us == 15_000
      assert new_state.response_status == 200

      assert [
               {"content-type", "application/json"},
               {"authorization", "[REDACTED]"}
             ] = new_state.response_headers
    end
  end

  describe "handle_response_finished/2" do
    setup %{state: state} do
      # Create a ChannelRequest first, since handle_response_finished needs it
      metadata = request_metadata()
      {:ok, state} = Handler.handle_request_started(metadata, state)

      # Add response_started state
      state =
        Map.merge(state, %{
          ttfb_us: 10_000,
          response_status: 200,
          response_headers: [{"content-type", "text/plain"}]
        })

      %{state: state}
    end

    test "creates ChannelEvent with correct fields", %{state: state} do
      result = finished_result(status: 200, duration_us: 50_000)

      assert {:ok, _state} = Handler.handle_response_finished(result, state)

      assert_receive {:channel_request_completed, _}, 1000

      event = Repo.one!(ChannelEvent)
      assert event.channel_request_id == state.channel_request.id
      assert event.type == :sink_response
      assert event.request_method == state.request_method
      assert event.request_path == "/test/path"
      assert event.response_status == 200
      assert event.latency_ms == 50
      assert event.ttfb_ms == 10
      assert event.error_message == nil
    end

    test "updates ChannelRequest state to success for 2xx", %{state: state} do
      result = finished_result(status: 200)
      Handler.handle_response_finished(result, state)
      assert_receive {:channel_request_completed, _}, 1000

      request = Repo.get!(ChannelRequest, state.channel_request.id)
      assert request.state == :success
      assert request.completed_at != nil
    end

    test "updates ChannelRequest state to failed for 4xx", %{state: state} do
      state = %{state | response_status: 404}
      result = finished_result(status: 404)
      Handler.handle_response_finished(result, state)
      assert_receive {:channel_request_completed, _}, 1000

      request = Repo.get!(ChannelRequest, state.channel_request.id)
      assert request.state == :failed
    end

    test "updates ChannelRequest state to timeout on timeout error", %{
      state: state
    } do
      result = finished_result(status: nil, error: {:timeout, :recv_response})
      Handler.handle_response_finished(result, state)
      assert_receive {:channel_request_completed, _}, 1000

      request = Repo.get!(ChannelRequest, state.channel_request.id)
      assert request.state == :timeout
    end

    test "updates ChannelRequest state to error on other errors", %{
      state: state
    } do
      result =
        finished_result(
          status: nil,
          error: %Mint.TransportError{reason: :econnrefused}
        )

      Handler.handle_response_finished(result, state)
      assert_receive {:channel_request_completed, _}, 1000

      request = Repo.get!(ChannelRequest, state.channel_request.id)
      assert request.state == :error
    end

    test "creates error event type when error present", %{state: state} do
      result = finished_result(status: nil, error: :some_error)
      Handler.handle_response_finished(result, state)
      assert_receive {:channel_request_completed, _}, 1000

      event = Repo.one!(ChannelEvent)
      assert event.type == :error
      assert event.error_message != nil
    end
  end

  # Helpers

  defp request_metadata(overrides \\ []) do
    %{
      request_id: Keyword.get(overrides, :request_id, Ecto.UUID.generate()),
      upstream_url:
        Keyword.get(overrides, :upstream_url, "http://localhost:4999"),
      method: Keyword.get(overrides, :method, "GET"),
      headers:
        Keyword.get(overrides, :headers, [
          {"content-type", "application/json"},
          {"host", "localhost"}
        ]),
      content_type: Keyword.get(overrides, :content_type, "application/json"),
      started_at:
        Keyword.get(overrides, :started_at, System.monotonic_time(:microsecond))
    }
  end

  defp finished_result(overrides) do
    observation = %{
      hash: "abc123",
      size: 100,
      body: nil,
      preview: "test body",
      duration_us: 1000,
      time_to_first_byte_us: 500
    }

    %{
      request_id: Keyword.get(overrides, :request_id, Ecto.UUID.generate()),
      request_observation:
        Keyword.get(overrides, :request_observation, observation),
      response_observation:
        Keyword.get(overrides, :response_observation, observation),
      error: Keyword.get(overrides, :error, nil),
      upstream_url:
        Keyword.get(overrides, :upstream_url, "http://localhost:4999"),
      method: Keyword.get(overrides, :method, "GET"),
      status: Keyword.get(overrides, :status, 200),
      duration_us: Keyword.get(overrides, :duration_us, 10_000)
    }
  end
end
