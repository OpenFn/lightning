defmodule LightningWeb.AdaptorIconControllerTest do
  use LightningWeb.ConnCase, async: false

  import Mox

  setup :set_mox_from_context
  setup :verify_on_exit!

  # Clean ETS cache entries that our tests rely on, so Plug.Static
  # fallthrough and prior test runs don't interfere.
  setup do
    Lightning.AdaptorData.Cache.invalidate("icon")
    Lightning.AdaptorData.Cache.invalidate("icon_manifest")
    :ok
  end

  describe "show/2" do
    test "serves a cached icon from DB/ETS", %{conn: conn} do
      # Use a fake adaptor name that has no file on disk so Plug.Static
      # passes through to the router.
      png_data = <<137, 80, 78, 71, 13, 10, 26, 10>>

      Lightning.AdaptorData.put(
        "icon",
        "fakexyz-square",
        png_data,
        "image/png"
      )

      Lightning.AdaptorData.Cache.invalidate("icon")

      conn = get(conn, "/images/adaptors/fakexyz-square.png")

      assert response(conn, 200) == png_data

      assert get_resp_header(conn, "content-type") == [
               "image/png; charset=utf-8"
             ]

      assert ["public, max-age=604800"] =
               get_resp_header(conn, "cache-control")
    end

    test "fetches icon from GitHub on cache miss and caches it",
         %{conn: conn} do
      png_data = <<137, 80, 78, 71, 13, 10, 26, 10, 0, 0>>

      Mox.expect(Lightning.Tesla.Mock, :call, fn env, _opts ->
        assert env.url =~
                 "raw.githubusercontent.com/OpenFn/adaptors/main/packages/fakexyz/assets/square.png"

        {:ok, %Tesla.Env{status: 200, body: png_data}}
      end)

      conn = get(conn, "/images/adaptors/fakexyz-square.png")

      assert response(conn, 200) == png_data

      # Verify it was stored in DB
      assert {:ok, entry} =
               Lightning.AdaptorData.get("icon", "fakexyz-square")

      assert entry.data == png_data
      assert entry.content_type == "image/png"
    end

    test "handles adaptor names with hyphens (e.g. fake-multi-word)",
         %{conn: conn} do
      png_data = <<1, 2, 3, 4>>

      Mox.expect(Lightning.Tesla.Mock, :call, fn env, _opts ->
        assert env.url =~
                 "/packages/fake-multi-word/assets/rectangle.png"

        {:ok, %Tesla.Env{status: 200, body: png_data}}
      end)

      conn = get(conn, "/images/adaptors/fake-multi-word-rectangle.png")

      assert response(conn, 200) == png_data
    end

    test "returns 404 when GitHub returns 404", %{conn: conn} do
      Mox.expect(Lightning.Tesla.Mock, :call, fn _env, _opts ->
        {:ok, %Tesla.Env{status: 404, body: ""}}
      end)

      conn = get(conn, "/images/adaptors/nonexistent99-square.png")
      assert response(conn, 404)
    end

    test "returns 502 on GitHub error", %{conn: conn} do
      Mox.expect(Lightning.Tesla.Mock, :call, fn _env, _opts ->
        {:error, :timeout}
      end)

      conn = get(conn, "/images/adaptors/fakexyz-square.png")
      assert response(conn, 502)
    end

    test "returns 400 for invalid filename format", %{conn: conn} do
      conn = get(conn, "/images/adaptors/invalid.png")
      assert response(conn, 400)
    end

    test "returns 400 for filename with unknown shape", %{conn: conn} do
      conn = get(conn, "/images/adaptors/fakexyz-circle.png")
      assert response(conn, 400)
    end
  end

  describe "manifest/2" do
    test "serves cached manifest from DB", %{conn: conn} do
      manifest =
        Jason.encode!(%{
          "fakexyz" => %{
            "square" => "/images/adaptors/fakexyz-square.png"
          }
        })

      Lightning.AdaptorData.put(
        "icon_manifest",
        "all",
        manifest,
        "application/json"
      )

      Lightning.AdaptorData.Cache.invalidate("icon_manifest")

      conn = get(conn, "/images/adaptors/adaptor_icons.json")

      assert json_response(conn, 200) == %{
               "fakexyz" => %{
                 "square" => "/images/adaptors/fakexyz-square.png"
               }
             }

      assert ["public, max-age=300"] =
               get_resp_header(conn, "cache-control")
    end

    test "returns empty JSON when no manifest is cached", %{conn: conn} do
      # Delete any existing manifest from DB
      Lightning.AdaptorData.delete("icon_manifest", "all")
      Lightning.AdaptorData.Cache.invalidate("icon_manifest")

      conn = get(conn, "/images/adaptors/adaptor_icons.json")

      assert json_response(conn, 200) == %{}
    end
  end
end
