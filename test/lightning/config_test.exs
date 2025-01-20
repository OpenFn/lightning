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
  end

  defp extract_from_config(config, key) do
    Application.get_env(:lightning, config) |> Keyword.get(key)
  end
end
