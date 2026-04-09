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
      request_id: Ecto.UUID.generate(),
      started_at: DateTime.utc_now(),
      request_path: "/test/path",
      client_identity: "127.0.0.1"
    }

    %{channel: channel, snapshot: snapshot, state: initial_state}
  end

  describe "handle_request_started/2" do
    test "creates a ChannelRequest in pending state", %{state: state} do
      metadata = request_metadata()

      assert {:ok, new_state} = Handler.handle_request_started(metadata, state)

      assert %ChannelRequest{} = new_state.channel_request
      assert new_state.channel_request.state == :pending
      assert new_state.channel_request.request_id == state.request_id
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

      event = Repo.one!(ChannelEvent)
      assert event.channel_request_id == state.channel_request.id
      assert event.type == :destination_response
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

      request = Repo.get!(ChannelRequest, state.channel_request.id)
      assert request.state == :success
      assert request.completed_at != nil
    end

    test "updates ChannelRequest state to failed for 4xx", %{state: state} do
      state = %{state | response_status: 404}
      result = finished_result(status: 404)
      Handler.handle_response_finished(result, state)

      request = Repo.get!(ChannelRequest, state.channel_request.id)
      assert request.state == :failed
    end

    test "updates ChannelRequest state to timeout on timeout error", %{
      state: state
    } do
      result = finished_result(status: nil, error: {:timeout, :recv_response})
      Handler.handle_response_finished(result, state)

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

      request = Repo.get!(ChannelRequest, state.channel_request.id)
      assert request.state == :error
    end

    test "creates error event type when error present", %{state: state} do
      result = finished_result(status: nil, error: :some_error)
      Handler.handle_response_finished(result, state)

      event = Repo.one!(ChannelEvent)
      assert event.type == :error
      assert event.error_message != nil
    end
  end

  # ---------------------------------------------------------------
  # Phase 1a contract tests — Philter 0.3.0 adaptation + new fields
  # ---------------------------------------------------------------
  #
  # These tests define the target interface after:
  # - D1: New columns on channel_events (body sizes, durations, query string)
  # - D2: Headers text → jsonb migration
  # - D4: Handler reads from Philter 0.3.0 result structure
  #
  # They will not compile/pass until Phase 1b implements the changes.

  describe "ChannelEvent changeset — new fields" do
    test "accepts body size fields" do
      attrs = %{
        channel_request_id: Ecto.UUID.generate(),
        type: :destination_response,
        request_body_size: 1024,
        response_body_size: 2048
      }

      changeset = ChannelEvent.changeset(%ChannelEvent{}, attrs)
      assert changeset.valid?
      assert changeset.changes.request_body_size == 1024
      assert changeset.changes.response_body_size == 2048
    end

    test "accepts per-direction duration fields" do
      attrs = %{
        channel_request_id: Ecto.UUID.generate(),
        type: :destination_response,
        request_send_us: 3_500,
        response_duration_us: 8_000
      }

      changeset = ChannelEvent.changeset(%ChannelEvent{}, attrs)
      assert changeset.valid?
      assert changeset.changes.request_send_us == 3_500
      assert changeset.changes.response_duration_us == 8_000
    end

    test "accepts request_query_string" do
      attrs = %{
        channel_request_id: Ecto.UUID.generate(),
        type: :destination_response,
        request_query_string: "page=1&limit=10"
      }

      changeset = ChannelEvent.changeset(%ChannelEvent{}, attrs)
      assert changeset.valid?
      assert changeset.changes.request_query_string == "page=1&limit=10"
    end

    test "new fields are all nullable" do
      attrs = %{
        channel_request_id: Ecto.UUID.generate(),
        type: :error,
        error_message: "nxdomain"
      }

      changeset = ChannelEvent.changeset(%ChannelEvent{}, attrs)
      assert changeset.valid?
      refute Map.has_key?(changeset.changes, :request_body_size)
      refute Map.has_key?(changeset.changes, :response_body_size)
      refute Map.has_key?(changeset.changes, :request_send_us)
      refute Map.has_key?(changeset.changes, :response_duration_us)
      refute Map.has_key?(changeset.changes, :request_query_string)
    end
  end

  describe "persist_completion — Philter 0.3.0 fields" do
    setup %{state: state} do
      metadata = request_metadata()
      {:ok, state} = Handler.handle_request_started(metadata, state)

      state =
        Map.merge(state, %{
          ttfb_us: 10_000,
          response_status: 200,
          response_headers: [{"content-type", "text/plain"}]
        })

      %{state: state}
    end

    test "uses timing.total_us for latency_ms", %{state: state} do
      result = philter_result(timing: %{total_us: 50_000, send_us: 2_000})

      assert {:ok, _state} = Handler.handle_response_finished(result, state)

      event = Repo.one!(ChannelEvent)
      assert event.latency_ms == 50
    end

    test "persists request_send_us from timing.send_us", %{state: state} do
      result = philter_result(timing: %{total_us: 50_000, send_us: 3_500})

      assert {:ok, _state} = Handler.handle_response_finished(result, state)

      event = Repo.one!(ChannelEvent)
      assert event.request_send_us == 3_500
    end

    test "persists response_duration_us from timing.recv_us",
         %{state: state} do
      result =
        philter_result(
          timing: %{total_us: 50_000, send_us: 2_000, recv_us: 8_000}
        )

      assert {:ok, _state} = Handler.handle_response_finished(result, state)

      event = Repo.one!(ChannelEvent)
      assert event.response_duration_us == 8_000
    end

    test "persists body sizes from observations", %{state: state} do
      result =
        philter_result(
          request_observation: %{
            hash: "req123",
            size: 1024,
            body: nil,
            preview: "request body"
          },
          response_observation: %{
            hash: "resp123",
            size: 2048,
            body: nil,
            preview: "response body"
          }
        )

      assert {:ok, _state} = Handler.handle_response_finished(result, state)

      event = Repo.one!(ChannelEvent)
      assert event.request_body_size == 1024
      assert event.response_body_size == 2048
    end

    test "persists query string from handler state", %{state: state} do
      state = Map.put(state, :query_string, "page=1&limit=10")
      result = philter_result()

      assert {:ok, _state} = Handler.handle_response_finished(result, state)

      event = Repo.one!(ChannelEvent)
      assert event.request_query_string == "page=1&limit=10"
    end

    test "nil phase timings when collect_timing is disabled", %{state: state} do
      result =
        philter_result(timing: %{total_us: 50_000, send_us: nil, recv_us: nil})

      assert {:ok, _state} = Handler.handle_response_finished(result, state)

      event = Repo.one!(ChannelEvent)
      assert event.request_send_us == nil
      assert event.response_duration_us == nil
      assert event.latency_ms == 50
    end
  end

  describe "header encoding — native jsonb" do
    setup %{state: state} do
      metadata =
        request_metadata(
          headers: [
            {"content-type", "application/json"},
            {"x-custom", "value"}
          ]
        )

      {:ok, state} = Handler.handle_request_started(metadata, state)

      state =
        Map.merge(state, %{
          ttfb_us: 10_000,
          response_status: 200,
          response_headers: [
            {"content-type", "text/plain"},
            {"x-resp", "val"}
          ]
        })

      %{state: state}
    end

    test "request headers round-trip as list without Jason.decode!", %{
      state: state
    } do
      result = philter_result()
      Handler.handle_response_finished(result, state)

      event = Repo.one!(ChannelEvent)

      # After jsonb migration, headers are native lists, not JSON strings
      assert is_list(event.request_headers)

      assert event.request_headers == [
               ["content-type", "application/json"],
               ["x-custom", "value"]
             ]
    end

    test "response headers round-trip as list without Jason.decode!", %{
      state: state
    } do
      result = philter_result()
      Handler.handle_response_finished(result, state)

      event = Repo.one!(ChannelEvent)

      assert is_list(event.response_headers)

      assert event.response_headers == [
               ["content-type", "text/plain"],
               ["x-resp", "val"]
             ]
    end

    test "nil headers remain nil", %{state: state} do
      state = Map.delete(state, :response_headers)

      result =
        philter_result(
          status: nil,
          error: %Mint.TransportError{reason: :econnrefused}
        )

      Handler.handle_response_finished(result, state)

      event = Repo.one!(ChannelEvent)
      assert event.response_headers == nil
    end
  end

  # Helpers

  defp request_metadata(overrides \\ []) do
    %{
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

  # Philter 0.3.0 result format:
  # - Observations are content-only (hash, size, preview, body)
  # - All timing lives in the top-level timing map
  defp philter_result(overrides \\ []) do
    observation = %{
      hash: "abc123",
      size: 100,
      body: nil,
      preview: "test body"
    }

    %{
      request_observation:
        Keyword.get(overrides, :request_observation, observation),
      response_observation:
        Keyword.get(overrides, :response_observation, observation),
      error: Keyword.get(overrides, :error, nil),
      upstream_url:
        Keyword.get(overrides, :upstream_url, "http://localhost:4999"),
      method: Keyword.get(overrides, :method, "GET"),
      status: Keyword.get(overrides, :status, 200),
      timing:
        Keyword.get(overrides, :timing, %{
          total_us: 10_000,
          send_us: 2_000,
          recv_us: 1_000
        })
    }
  end
end
