defmodule LightningWeb.Plugs.MetricsAuthTest do
  use LightningWeb.ConnCase, async: true

  import Plug.Test

  alias LightningWeb.Plugs.MetricsAuth

  setup do
    token = "test_token"

    Mox.stub(Lightning.MockConfig, :promex_metrics_endpoint_token, fn ->
      token
    end)
    Mox.stub(Lightning.MockConfig, :promex_metrics_endpoint_scheme, fn ->
      "http"
    end)

    %{token: token}
  end

  describe "metrics request and authorization required" do
    setup %{token: token} do
      Mox.stub(
        Lightning.MockConfig,
        :promex_metrics_endpoint_authorization_required?,
        fn -> true end
      )

      conn = conn(:get, "/metrics")

      %{conn: conn}
    end

    test "passes if the token and scheme match" do
      conn =
        conn
        |> put_req_header("authorization", "Bearer #{token}")
        |> MetricsAuth.call([])

      assert_passed_request(conn)
    end

    test "is unauthorized if no authorization header" do
      conn = 
        conn
        |> MetricsAuth.call([])

      assert_unauthorized_request(conn)
    end

    test "is unauthorized if no bearer token" do
      conn = 
        conn
        |> put_req_header("authorization", "Basic #{token}")
        |> MetricsAuth.call([])

      assert_unauthorized_request(conn)
    end

    test "is unauthorized if bearer token does not match" do
      conn = 
        conn
        |> put_req_header("authorization", "Bearer not-#{token}")
        |> MetricsAuth.call([])

      assert_unauthorized_request(conn)
    end

    test "is unauthorised if the scheme does not match" do
      Mox.stub(Lightning.MockConfig, :promex_metrics_endpoint_scheme, fn ->
        "https"
      end)
    
      conn = 
        conn
        |> put_req_header("authorization", "Bearer #{token}")
        |> MetricsAuth.call([])

      assert_unauthorized_request(conn)
    end

    test "responds with a 401", %{conn: conn} do
      conn = MetricsAuth.call(conn, [])

      assert_unauthorized_request?(conn)
      # assert conn.status == 401
      # assert get_resp_header(conn, "www-authenticate") == ["Bearer"]
      # assert conn.resp_body == "Unauthorized"
      # assert conn.halted
    end

  end

  def assert_passed_request?(conn) do
    assert conn.status == nil
    assert get_resp_header(conn, "www-authenticate") == []
    assert conn.resp_body == nil
    refute conn.halted
  end

  def unauthorized_request?(conn) do
    assert conn.status == 401
    assert get_resp_header(conn, "www-authenticate") == ["Bearer"]
    assert conn.resp_body == "Unauthorized"
    assert conn.halted
  end
end
