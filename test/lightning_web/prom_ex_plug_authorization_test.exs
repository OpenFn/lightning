defmodule LightningWeb.PromExPlugAuthorizationTest do
  use LightningWeb.ConnCase, async: true

  setup %{conn: conn} do
    token = "foo-bar-baz"

    update_promex_config(
      metrics_endpoint_token: token,
      metrics_endpoint_scheme: "http"
    )

    %{conn: conn, token: token}
  end

  test "returns true if bearer token and scheme match",
       %{conn: conn, token: token} do
    new_conn =
      conn |> Plug.Conn.put_req_header("authorization", "Bearer #{token}")

    result = LightningWeb.PromExPlugAuthorization.call(new_conn, nil)

    assert result
  end

  test "returns false if there is no authorization header", %{conn: conn} do
    result = LightningWeb.PromExPlugAuthorization.call(conn, nil)

    refute result
  end

  test "returns false if authorization header does not contain a bearer token",
       %{conn: conn, token: token} do
    new_conn =
      conn |> Plug.Conn.put_req_header("authorization", "Basic #{token}")

    result = LightningWeb.PromExPlugAuthorization.call(new_conn, nil)

    refute result
  end

  test "returns false if authorization header contains incorrect bearer token",
       %{conn: conn, token: token} do
    new_conn =
      conn |> Plug.Conn.put_req_header("authorization", "Basic not-#{token}")

    result = LightningWeb.PromExPlugAuthorization.call(new_conn, nil)

    refute result
  end

  test "returns false if scheme does not match", %{conn: conn, token: token} do
    update_promex_config(
      metrics_endpoint_token: token,
      metrics_endpoint_scheme: "https"
    )

    new_conn =
      conn |> Plug.Conn.put_req_header("authorization", "Bearer #{token}")

    result = LightningWeb.PromExPlugAuthorization.call(new_conn, nil)

    refute result
  end

  defp update_promex_config(overrides) do
    new_config =
      Application.get_env(:lightning, Lightning.PromEx)
      |> Keyword.merge(overrides)

    Application.put_env(:lightning, Lightning.PromEx, new_config)
  end
end
