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

  describe "init" do
    test "returns the provided options as they are" do
      assert MetricsAuth.init(a: 1, b: 2) == [a: 1, b: 2]
    end
  end

  describe "metrics request and authorization required" do
    setup do
      Mox.stub(
        Lightning.MockConfig,
        :promex_metrics_endpoint_authorization_required?,
        fn -> true end
      )

      conn = conn(:get, "/metrics")

      %{conn: conn}
    end

    test "passes if the token and scheme match", %{conn: conn, token: token} do
      conn =
        conn
        |> put_req_header("authorization", "Bearer #{token}")
        |> MetricsAuth.call([])

      assert_passed_request?(conn)
    end

    test "is unauthorized if no authorization header", %{conn: conn} do
      conn =
        conn
        |> MetricsAuth.call([])

      assert_unauthorized_request?(conn)
    end

    test "is unauthorized if no bearer token", %{conn: conn, token: token} do
      conn =
        conn
        |> put_req_header("authorization", "Basic #{token}")
        |> MetricsAuth.call([])

      assert_unauthorized_request?(conn)
    end

    test "is unauthorized if bearer token does not match", %{
      conn: conn,
      token: token
    } do
      conn =
        conn
        |> put_req_header("authorization", "Bearer not-#{token}")
        |> MetricsAuth.call([])

      assert_unauthorized_request?(conn)
    end

    test "is unauthorised if the scheme does not match",
         %{conn: conn, token: token} do
      Mox.stub(Lightning.MockConfig, :promex_metrics_endpoint_scheme, fn ->
        "https"
      end)

      conn =
        conn
        |> put_req_header("authorization", "Bearer #{token}")
        |> MetricsAuth.call([])

      assert_unauthorized_request?(conn)
    end
  end

  describe "not metrics and authorization required" do
    setup do
      Mox.stub(
        Lightning.MockConfig,
        :promex_metrics_endpoint_authorization_required?,
        fn -> true end
      )

      conn = conn(:get, "/not-metrics")

      %{conn: conn}
    end

    test "passes the request regardless of what is provided", %{conn: conn} do
      conn = conn |> MetricsAuth.call([])

      assert_passed_request?(conn)
    end
  end

  describe "metrics request but authorization not required" do
    setup do
      Mox.stub(
        Lightning.MockConfig,
        :promex_metrics_endpoint_authorization_required?,
        fn -> false end
      )

      conn = conn(:get, "/metrics")

      %{conn: conn}
    end

    test "passes the request regardless of what is provided", %{conn: conn} do
      conn = conn |> MetricsAuth.call([])

      assert_passed_request?(conn)
    end
  end

  def assert_passed_request?(conn) do
    assert conn.status == nil
    assert get_resp_header(conn, "www-authenticate") == []
    assert conn.resp_body == nil
    refute conn.halted
  end

  def assert_unauthorized_request?(conn) do
    assert conn.status == 401
    assert get_resp_header(conn, "www-authenticate") == ["Bearer"]
    assert conn.resp_body == "Unauthorized"
    assert conn.halted
  end
end
