defmodule Lightning.Channels.PromExPlugin do
  @moduledoc """
  PromEx plugin exposing metrics for the Channels HTTP reverse-proxy.

  Three metrics are emitted, all tagged by `project_id`:

    * `lightning_channel_proxy_requests_started_total` — counter incremented
      after channel resolution.
    * `lightning_channel_proxy_requests_finished_total` — counter incremented
      on every request leaving the proxy plug.
    * `lightning_channel_proxy_request_duration_milliseconds` — distribution
      of total time spent in the proxy plug.

  Concurrent open connections can be derived in Grafana as
  `requests_started_total - requests_finished_total` per project.

  The started counter attaches to a custom
  `[:lightning, :channel_proxy, :request, :counted]` event rather than the
  span's `:start` event. This is deliberate: span start metadata is
  captured before channel lookup, so it cannot carry the resolved
  `project_id`. The `:counted` event is emitted immediately after the
  channel is resolved (or in the not-found branch, tagged
  `project_id="unknown"`), so the started and finished counters share a
  consistent label set.

  Requests that fail channel lookup (404 or invalid UUID) are tagged
  `project_id="unknown"`, which surfaces probing or scanning behaviour.
  Authentication failures against an existing channel still surface the
  real `project_id`.
  """

  use PromEx.Plugin

  alias Telemetry.Metrics

  @request_counted_event [:lightning, :channel_proxy, :request, :counted]
  @request_stop_event [:lightning, :channel_proxy, :request, :stop]

  @impl true
  def event_metrics(_opts) do
    [
      Event.build(
        :lightning_channel_proxy_event_metrics,
        [
          Metrics.counter(
            [:lightning, :channel_proxy, :requests, :started, :total],
            event_name: @request_counted_event,
            description: "Total channel proxy requests started.",
            tags: [:project_id]
          ),
          Metrics.counter(
            [:lightning, :channel_proxy, :requests, :finished, :total],
            event_name: @request_stop_event,
            description: "Total channel proxy requests finished.",
            tags: [:project_id]
          ),
          distribution(
            [:lightning, :channel_proxy, :request, :duration, :milliseconds],
            event_name: @request_stop_event,
            description: "Channel proxy request duration in milliseconds.",
            measurement: :duration,
            unit: {:native, :millisecond},
            tags: [:project_id],
            reporter_options: [
              buckets: [10, 50, 100, 250, 500, 1000, 2500, 5000, 10_000]
            ]
          )
        ]
      )
    ]
  end
end
