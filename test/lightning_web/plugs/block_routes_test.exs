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

  describe "through the :browser pipeline" do
    setup do
      stub(Lightning.MockConfig, :check_flag?, fn _flag -> false end)
      :ok
    end

    # Non-normalised spellings that the router still dispatches to the
    # registration controller must hit the same block, not slip past it.
    # `/users/%72egister` is the case that exercises the fix's per-segment
    # decode: the adapter leaves the segment percent-encoded in `path_info` and
    # the router only decodes it at dispatch, so the gate has to decode too.
    #
    # A bare `//users/register` can't be driven through the test client here —
    # `Plug.Test`'s `URI.parse` reads `users` as the URI authority and rewrites
    # the target to `/register` — so that spelling is covered by manual
    # verification against a real cowboy request rather than this test.
    for path <- [
          "/users/register",
          "/users/register/",
          "///users/register",
          "/users/%72egister"
        ] do
      test "blocks GET #{path} when :allow_signup is false", %{conn: conn} do
        conn = get(conn, unquote(path))

        assert conn.status == 404

        assert conn.resp_body ==
                 "Self-signup has been disabled for this instance. Please contact the administrator."
      end
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
