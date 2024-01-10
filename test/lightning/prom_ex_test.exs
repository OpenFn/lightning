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

  test "returns enabled plugins" do
    stalled_attempt_threshold_seconds =
      Application.get_env(:lightning, :metrics)[
        :stalled_attempt_threshold_seconds
      ]

    expected = [
      PromEx.Plugins.Application,
      PromEx.Plugins.Beam,
      {PromEx.Plugins.Phoenix,
       router: LightningWeb.Router, endpoint: LightningWeb.Endpoint},
      PromEx.Plugins.Ecto,
      PromEx.Plugins.Oban,
      PromEx.Plugins.PhoenixLiveView,
      {Lightning.Attempts.PromExPlugin,
       stalled_attempt_threshold_seconds: stalled_attempt_threshold_seconds}
    ]

    assert Lightning.PromEx.plugins() == expected
  end

  defp update_promex_config(overrides) do
    new_config =
      Application.get_env(:lightning, Lightning.PromEx)
      |> Keyword.merge(overrides)

    Application.put_env(:lightning, Lightning.PromEx, new_config)
  end
end
