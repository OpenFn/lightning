defmodule Lightning.Factories.ChannelFactories do
  @moduledoc false

  defmacro __using__(_opts) do
    quote do
      def channel_factory do
        %Lightning.Channels.Channel{
          project: build(:project),
          name: sequence(:channel_name, &"channel-#{&1}"),
          destination_url:
            sequence(
              :channel_destination_url,
              &"https://example.com/destination/#{&1}"
            ),
          enabled: true
        }
      end

      def channel_auth_method_factory do
        %Lightning.Channels.ChannelAuthMethod{
          role: :client,
          webhook_auth_method: build(:webhook_auth_method)
        }
      end

      def channel_snapshot_factory do
        %Lightning.Channels.ChannelSnapshot{
          lock_version: 1,
          name: sequence(:channel_snapshot_name, &"channel-#{&1}"),
          destination_url: "https://example.com/destination",
          enabled: true
        }
      end

      def channel_request_factory do
        %Lightning.Channels.ChannelRequest{
          request_id: sequence(:channel_request_id, &"req-#{&1}"),
          client_identity: "127.0.0.1",
          state: :pending,
          started_at: DateTime.utc_now()
        }
      end

      def channel_event_factory do
        %Lightning.Channels.ChannelEvent{
          type: :destination_response,
          request_method: "POST",
          request_path: "/api/v1/data",
          request_headers: [
            ["content-type", "application/json"],
            ["authorization", "[REDACTED]"]
          ],
          request_body_preview: ~s({"key":"value"}),
          request_body_hash: "abc123def456",
          request_body_size: 15,
          response_status: 200,
          response_headers: [["content-type", "application/json"]],
          response_body_preview: ~s({"status":"ok"}),
          response_body_hash: "def456abc123",
          response_body_size: 15,
          latency_us: 350_000,
          ttfb_us: 280_000,
          request_send_us: 5000,
          response_duration_us: 65000
        }
      end

      def channel_error_event_factory do
        %Lightning.Channels.ChannelEvent{
          type: :error,
          request_method: "POST",
          request_path: "/api/v1/data",
          request_headers: [["content-type", "application/json"]]
        }
      end
    end
  end
end
