defmodule LightningWeb.PromEx.MetricsEndpointTest do
  use LightningWeb.ConnCase, async: true

  describe "unauthorized request to GET /metrics" do
    setup do
      Mox.stub(
        Lightning.MockConfig,
        :promex_metrics_endpoint_authorization_required?,
        fn -> true end
      )

      :ok
    end

    test "returns 401", %{conn: conn} do
      conn = get(conn, "/metrics")

      assert conn.status == 401
    end
  end
end
