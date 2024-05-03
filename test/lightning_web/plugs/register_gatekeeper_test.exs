defmodule MyAppWeb.Plugs.RegisterGatekeeperTest do
  use LightningWeb.ConnCase, async: true

  import Plug.Test

  alias LightningWeb.Plugs.RegisterGatekeeper

  describe("call/2 when registration is disabled") do
    setup do
      Application.put_env(:lightning, :disable_registration, true)
      :ok
    end

    test "returns 404 for /users/register" do
      conn = conn(:get, "/users/register") |> RegisterGatekeeper.call([])

      assert conn.status == 404

      assert get_resp_header(conn, "content-type")
             |> Enum.any?(fn header -> header == "text/plain; charset=utf-8" end)

      assert conn.resp_body == "404 Page not found"
    end

    test "passes through for other paths" do
      conn = conn(:get, "/other/path") |> RegisterGatekeeper.call([])

      assert conn.status != 404
    end
  end

  describe "call/2 when registration is enabled" do
    setup do
      Application.put_env(:lightning, :disable_registration, false)
      :ok
    end

    test "passes through for /users/register" do
      conn = conn(:get, "/users/register") |> RegisterGatekeeper.call([])

      assert conn.status != 404
    end

    test "passes through for other paths" do
      conn = conn(:get, "/other/path") |> RegisterGatekeeper.call([])

      assert conn.status != 404
    end
  end
end
