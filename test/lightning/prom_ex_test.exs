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

    Mox.stub(
      Lightning.MockConfig,
      :metrics_run_performance_age_seconds,
      fn -> 10 end
    )

    Mox.stub(
      Lightning.MockConfig,
      :metrics_run_queue_metrics_period_seconds,
      fn -> 20 end
    )

    Mox.stub(
      Lightning.MockConfig,
      :metrics_stalled_run_threshold_seconds,
      fn -> 30 end
    )

    Mox.stub(
      Lightning.MockConfig,
      :metrics_unclaimed_run_threshold_seconds,
      fn -> 40 end
    )

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
        run_queue_metrics_period_seconds: 20,
        run_performance_age_seconds: 10,
        stalled_run_threshold_seconds: 30,
        unclaimed_run_threshold_seconds: 40
      },
      Lightning.PromExTestPlugin,
      Lightning.Projects.SandboxPromExPlugin,
      FooPlugin,
      BarPlugin
    ]

    assert Lightning.PromEx.plugins() == expected
  end

  test "seeds event metrics, including external metrics" do
    Mox.stub(Lightning.MockConfig, :external_metrics_module, fn ->
      Lightning.PromExTest.ExternalMetrics
    end)

    lightning_prom_ex_test_event = [:lightning, :prom_ex_test]
    lost_runs_count_event = [:lightning, :run, :lost]
    test_event = [:promex, :external, :test, :event]

    ref =
      :telemetry_test.attach_event_handlers(
        self(),
        [
          lightning_prom_ex_test_event,
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
      %{}
    }

    assert_received {
      ^lightning_prom_ex_test_event,
      ^ref,
      %{count: 1},
      %{}
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
      :telemetry.execute([:promex, :external, :test, :event], %{count: 42}, %{})
    end
  end
end
