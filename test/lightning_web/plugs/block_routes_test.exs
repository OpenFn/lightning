defmodule MyAppWeb.Plugs.BlockRoutesTest do
  use LightningWeb.ConnCase, async: true

  import Plug.Test
  import Mox

  alias LightningWeb.Plugs.BlockRoutes

  setup :verify_on_exit!

  Mox.stub_with(Lightning.MockConfig, Lightning.Config.API)

  describe "call/2 when specific routes are blocked" do
    setup do
      {:ok,
       routes_flags: [
         {"/users/register", :allow_signup,
          "Self-signup has been disabled for this instance. Please contact the administrator."},
         {"/other/path", :allow_other, "This other feature is available."}
       ]}
    end

    test "returns 404 with specific message for /users/register when :allow_signup is false",
         %{
           routes_flags: routes_flags
         } do
      expect(Lightning.MockConfig, :check_flag?, fn _flag ->
        false
      end)

      conn = conn(:get, "/users/register") |> BlockRoutes.call(routes_flags)

      assert conn.status == 404

      assert get_resp_header(conn, "content-type")
             |> Enum.any?(fn header -> header == "text/plain; charset=utf-8" end)

      assert conn.resp_body ==
               "Self-signup has been disabled for this instance. Please contact the administrator."
    end

    test "passes through for /users/register when :allow_signup is true",
         %{
           routes_flags: routes_flags
         } do
      expect(Lightning.MockConfig, :check_flag?, fn _flag ->
        true
      end)

      conn = conn(:get, "/users/register") |> BlockRoutes.call(routes_flags)
      assert conn.status != 400
    end

    test "passes through for /other/path when feature is enabled", %{
      routes_flags: routes_flags
    } do
      conn = conn(:get, "/other/path") |> BlockRoutes.call(routes_flags)
      assert conn.status != 404
    end

    test "passes through for an unrelated path", %{routes_flags: routes_flags} do
      conn = conn(:get, "/unrelated/path") |> BlockRoutes.call(routes_flags)
      assert conn.status != 404
    end
  end

  describe "call/2 with all routes enabled" do
    setup do
      expect(Lightning.MockConfig, :check_flag?, fn _flag -> true end)

      routes_flags = [
        {"/users/register", :allow_signup, "Self-signup is enabled."},
        {"/other/path", :allow_other, "This other feature is available."}
      ]

      {:ok, routes_flags: routes_flags}
    end

    test "passes through for all routes", %{routes_flags: routes_flags} do
      conn = conn(:get, "/users/register") |> BlockRoutes.call(routes_flags)
      assert conn.status != 404
      conn = conn(:get, "/other/path") |> BlockRoutes.call(routes_flags)
      assert conn.status != 404
    end
  end
end
