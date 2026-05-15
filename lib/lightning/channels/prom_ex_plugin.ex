defmodule Lightning.Channels.PromExPlugin do
  @moduledoc """
  PromEx plugin exposing metrics for the Channels HTTP reverse-proxy.

  Telemetry is layered into two spans:

    * **Outer `:inbound` span** — wraps every `/channels/*` hit, including
      probes with invalid UUIDs or unknown channel IDs. Tagged by
      `outcome` (`:resolved | :invalid_uuid | :unknown_channel`) so we can
      surface edge traffic and scanning behaviour without leaking the raw
      URL segment into metric labels.
    * **Inner `:request` span** — opens only after channel resolution
      succeeds. Tagged by `project_id` (a bounded, trusted value), it
      tracks real proxy operations: how many start, how long they take,
      and what their outcome is.

  Metrics emitted:

    * `lightning_channel_proxy_inbound_total{outcome}` — counter on the
      outer span's `:stop` event. Counts every inbound request, bucketed
      by outcome.
    * `lightning_channel_proxy_requests_started_total{project_id}` —
      counter on the inner span's `:start` event. Started metadata
      already carries the resolved `project_id`, so no separate counted
      event is needed.
    * `lightning_channel_proxy_request_duration_milliseconds{project_id}`
      — distribution of total time spent in the inner span. Its
      `_count` series doubles as the finished-request total, so a
      separate finished counter is not emitted.

  Concurrent in-flight requests cannot be derived precisely from these
  counters — request lifetimes (ms) are far shorter than typical scrape
  intervals (s), so any `started − finished` subtraction is ~always zero
  at scrape boundaries. 
  """

  use PromEx.Plugin

  alias Telemetry.Metrics

  @inbound_stop_event [:lightning, :channel_proxy, :inbound, :stop]
  @request_start_event [:lightning, :channel_proxy, :request, :start]
  @request_stop_event [:lightning, :channel_proxy, :request, :stop]

  @impl true
  def event_metrics(_opts) do
    [
      Event.build(
        :lightning_channel_proxy_event_metrics,
        [
          Metrics.counter(
            [:lightning, :channel_proxy, :inbound, :total],
            event_name: @inbound_stop_event,
            description:
              "Total inbound /channels/* requests, tagged by outcome.",
            tags: [:outcome]
          ),
          Metrics.counter(
            [:lightning, :channel_proxy, :requests, :started, :total],
            event_name: @request_start_event,
            description: "Total channel proxy requests started.",
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
