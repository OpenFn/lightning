defmodule Lightning.TelemetryTest do
  use ExUnit.Case, async: true

  test "returns a collection of metrics" do
    metrics =
      LightningWeb.Telemetry.metrics()
      |> Enum.map(fn metric ->
        %type{event_name: event_name} = metric
        [type, event_name]
      end)

    assert metrics |> summary?([:lightning, :workorder, :webhook, :stop])
    assert metrics |> distribution?([:lightning, :workorder, :webhook, :stop])

    assert metrics |> summary?([:oban, :job, :stop])
    assert metrics |> distribution?([:oban, :job, :stop])

    assert metrics |> summary?([:lightning, :ui, :projects, :history, :stop])

    assert metrics
           |> distribution?([:lightning, :ui, :projects, :history, :stop])
  end

  test "webhook api metric are restricted to :ok responses only" do
    metrics =
      LightningWeb.Telemetry.metrics()
      |> Enum.filter(
        &(&1.event_name == [:lightning, :workorder, :webhook, :stop])
      )

    include_ok_status = & &1.keep.(%{status: :ok})
    exclude_other_status = &(!&1.keep.(%{status: :not_ok}))

    assert metrics |> Enum.all?(include_ok_status)
    assert metrics |> Enum.all?(exclude_other_status)
  end

  defp summary?(metrics, name) do
    metrics |> Enum.member?([Telemetry.Metrics.Summary, name])
  end

  defp distribution?(metrics, name) do
    metrics |> Enum.member?([Telemetry.Metrics.Distribution, name])
  end
end
