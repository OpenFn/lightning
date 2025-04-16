defmodule Lightning.PromExTest do
  use ExUnit.Case, async: true

  test "returns dashboard config" do
    update_promex_config(datasource_id: "foo")

    expected = [datasource_id: "foo", default_selected_interval: "30s"]

    assert Lightning.PromEx.dashboard_assigns() == expected
  end

  test "returns enabled dashboards" do
    expected = [
      {:prom_ex, "application.json"},
      {:prom_ex, "beam.json"},
      {:prom_ex, "phoenix.json"},
      {:prom_ex, "ecto.json"},
      {:prom_ex, "oban.json"},
      {:prom_ex, "phoenix_live_view.json"}
    ]

    assert Lightning.PromEx.dashboards() == expected
  end

  test "returns enabled plugins including external plugins" do
    Mox.stub(Lightning.MockConfig, :external_metrics_module, fn ->
      Lightning.PromExTest.ExternalMetrics
    end)

    stalled_run_threshold_seconds =
      Application.get_env(:lightning, :metrics)[
        :stalled_run_threshold_seconds
      ]

    performance_age_seconds =
      Application.get_env(:lightning, :metrics)[
        :run_performance_age_seconds
      ]

    run_metrics_period =
      Application.get_env(:lightning, :metrics)[
        :run_queue_metrics_period_seconds
      ]

    expected = [
      PromEx.Plugins.Application,
      PromEx.Plugins.Beam,
      {PromEx.Plugins.Phoenix,
       router: LightningWeb.Router, endpoint: LightningWeb.Endpoint},
      PromEx.Plugins.Ecto,
      {PromEx.Plugins.Oban, [oban_supervisors: [Lightning.Oban]]},
      PromEx.Plugins.PhoenixLiveView,
      {
        Lightning.Runs.PromExPlugin,
        run_queue_metrics_period_seconds: run_metrics_period,
        run_performance_age_seconds: performance_age_seconds,
        stalled_run_threshold_seconds: stalled_run_threshold_seconds
      },
      FooPlugin,
      BarPlugin
    ]

    assert Lightning.PromEx.plugins() == expected
  end

  test "seeds any external event metrics to ensure presence of the metrics" do
    Mox.stub(Lightning.MockConfig, :external_metrics_module, fn ->
      Lightning.PromExTest.ExternalMetrics
    end)

    lost_runs_count_event = [:lightning, :run, :lost]
    test_event = [:promex, :test, :event]

    ref =
      :telemetry_test.attach_event_handlers(
        self(),
        [
          lost_runs_count_event,
          test_event
        ]
      )

    Lightning.PromEx.seed_event_metrics()

    assert_received {^test_event, ^ref, %{count: 42}, %{}}
    assert_received {
                      ^lost_runs_count_event,
                      ^ref,
                      %{count: 1},
                      %{seed_event: true, worker_name: "n/a"}
                    }
  end

  defp update_promex_config(overrides) do
    new_config =
      Application.get_env(:lightning, Lightning.PromEx)
      |> Keyword.merge(overrides)

    Application.put_env(:lightning, Lightning.PromEx, new_config)
  end

  defmodule ExternalMetrics do
    def plugins do
      [FooPlugin, BarPlugin]
    end

    def seed_event_metrics do
      :telemetry.execute([:promex, :test, :event], %{count: 42}, %{})
    end
  end
end
