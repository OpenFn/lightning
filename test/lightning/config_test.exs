defmodule Lightning.Configtest do
  use ExUnit.Case, async: true

  alias Lightning.Config.API

  describe "API" do
    test "returns the appropriate PromEx endpoint auth setting" do
      expected =
        extract_from_config(
          Lightning.PromEx,
          :metrics_endpoint_authorization_required
        )

      actual = API.promex_metrics_endpoint_authorization_required?()

      assert expected == actual
    end

    test "returns the appropriate Promex endpoint token" do
      expected =
        extract_from_config(Lightning.PromEx, :metrics_endpoint_token)

      actual = API.promex_metrics_endpoint_token()

      assert expected == actual
    end

    test "returns the appropriate PromEx endpoint scheme" do
      expected =
        extract_from_config(Lightning.PromEx, :metrics_endpoint_scheme)

      actual = API.promex_metrics_endpoint_scheme()

      assert expected == actual
    end

    test "indicates if the tracking of UI metrics is enabled" do
      expected =
        extract_from_config(:ui_metrics_tracking, :enabled)

      actual = API.ui_metrics_tracking_enabled?()

      assert expected == actual
    end

    test "returns module responsible for injecting external metric plugins" do
      expected =
        extract_from_config(Lightning.Extensions, :external_metrics)

      refute expected == nil

      actual = API.external_metrics_module()

      assert expected == actual
    end

    test "returns number of seconds that constitutes stalled run threshold" do
      expected =
        extract_from_config(
          :metrics,
          :stalled_run_threshold_seconds
        )

      actual = API.metrics_stalled_run_threshold_seconds()

      assert expected == actual
    end

    test "returns max allowable age of a run when considering run performance" do
      expected =
        extract_from_config(
          :metrics,
          :run_performance_age_seconds
        )

      actual = API.metrics_run_performance_age_seconds()

      assert expected == actual
    end

    test "returns the polling period in seconds for run queue metrics" do
      expected =
        extract_from_config(
          :metrics,
          :run_queue_metrics_period_seconds
        )

      actual = API.metrics_run_queue_metrics_period_seconds()

      assert expected == actual
    end
  end

  defp extract_from_config(config, key) do
    Application.get_env(:lightning, config) |> Keyword.get(key)
  end
end
