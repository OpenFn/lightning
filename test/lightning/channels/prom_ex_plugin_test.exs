defmodule Lightning.Channels.PromExPluginTest do
  use ExUnit.Case, async: true

  alias Lightning.Channels.PromExPlugin

  @started_name [:lightning, :channel_proxy, :requests, :started, :total]
  @duration_name [:lightning, :channel_proxy, :request, :duration, :milliseconds]

  describe "event_metrics/1" do
    test "returns exactly one Event group containing the two channel-proxy metrics" do
      assert [
               %PromEx.MetricTypes.Event{
                 group_name: :lightning_channel_proxy_event_metrics,
                 metrics: metrics
               }
             ] = PromExPlugin.event_metrics([])

      assert Enum.map(metrics, & &1.name) |> Enum.sort() ==
               Enum.sort([@started_name, @duration_name])
    end

    test "every metric is tagged by :project_id only" do
      [%{metrics: metrics}] = PromExPlugin.event_metrics([])

      assert Enum.all?(metrics, fn metric -> metric.tags == [:project_id] end)
    end

    test "started listens to :counted (not :start) so project_id is resolved" do
      # Regression guard: if started_total were attached to the span's :start
      # event, the project_id tag would always be "unknown" (start metadata is
      # captured before channel lookup). It must attach to :counted, which is
      # emitted post-resolution.
      [%{metrics: metrics}] = PromExPlugin.event_metrics([])

      started = find_metric(metrics, @started_name)

      assert %Telemetry.Metrics.Counter{
               event_name: [:lightning, :channel_proxy, :request, :counted],
               tags: [:project_id]
             } = started
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
