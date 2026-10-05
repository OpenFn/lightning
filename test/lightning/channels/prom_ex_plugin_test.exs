defmodule Lightning.Channels.PromExPluginTest do
  use ExUnit.Case, async: true

  alias Lightning.Channels.PromExPlugin

  @inbound_name [:lightning, :channel_proxy, :inbound, :total]
  @started_name [:lightning, :channel_proxy, :requests, :started, :total]
  @duration_name [:lightning, :channel_proxy, :request, :duration, :milliseconds]

  describe "event_metrics/1" do
    test "returns exactly one Event group containing the three channel-proxy metrics" do
      assert [
               %PromEx.MetricTypes.Event{
                 group_name: :lightning_channel_proxy_event_metrics,
                 metrics: metrics
               }
             ] = PromExPlugin.event_metrics([])

      assert Enum.map(metrics, & &1.name) |> Enum.sort() ==
               Enum.sort([@inbound_name, @started_name, @duration_name])
    end

    test "inner-span metrics are tagged by :project_id only" do
      [%{metrics: metrics}] = PromExPlugin.event_metrics([])

      project_tagged = [
        find_metric(metrics, @started_name),
        find_metric(metrics, @duration_name)
      ]

      assert Enum.all?(project_tagged, fn metric ->
               metric.tags == [:project_id]
             end)
    end

    test "started listens to the inner span's :start event so project_id is resolved" do
      # Regression guard: with the outer/inner span split, the inner
      # :request span only opens once a channel is resolved, so its
      # :start metadata already carries the real project_id. The started
      # counter must therefore attach to :request, :start.
      [%{metrics: metrics}] = PromExPlugin.event_metrics([])

      started = find_metric(metrics, @started_name)

      assert %Telemetry.Metrics.Counter{
               event_name: [:lightning, :channel_proxy, :request, :start],
               tags: [:project_id]
             } = started
    end

    test "inbound_total is a counter on the outer span's :stop event, tagged by :outcome" do
      [%{metrics: metrics}] = PromExPlugin.event_metrics([])

      inbound = find_metric(metrics, @inbound_name)

      assert %Telemetry.Metrics.Counter{
               event_name: [:lightning, :channel_proxy, :inbound, :stop],
               tags: [:outcome]
             } = inbound
    end

    test "duration is a distribution on the stop event with non-empty buckets" do
      [%{metrics: metrics}] = PromExPlugin.event_metrics([])

      duration = find_metric(metrics, @duration_name)

      assert %Telemetry.Metrics.Distribution{
               event_name: [:lightning, :channel_proxy, :request, :stop],
               tags: [:project_id],
               unit: :millisecond,
               reporter_options: reporter_options
             } = duration

      buckets = Keyword.fetch!(reporter_options, :buckets)
      assert is_list(buckets)
      assert buckets != []
      assert Enum.all?(buckets, &is_number/1)
    end
  end

  defp find_metric(metrics, name), do: Enum.find(metrics, &(&1.name == name))
end
