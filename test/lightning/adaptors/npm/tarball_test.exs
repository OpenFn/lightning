defmodule Lightning.Adaptors.NPM.TarballTest do
  use ExUnit.Case, async: false

  import Lightning.Adaptors.NPMTestHelpers, only: [build_tarball: 1]

  alias Lightning.Adaptors.NPM.Tarball

  setup do
    bypass = Bypass.open()

    # No :registry_url / :jsdelivr_url needed — Tarball uses absolute URLs
    # passed in by callers (resolved from the packument). We do still need
    # an http_timeout to ride through the Finch adapter cleanly.
    Application.put_env(:lightning, Lightning.Adaptors.NPM, http_timeout: 1_000)

    prev_adapter = Application.get_env(:tesla, :adapter)

    Application.put_env(
      :tesla,
      :adapter,
      {Tesla.Adapter.Finch, name: Lightning.Finch}
    )

    on_exit(fn ->
      Application.delete_env(:lightning, Lightning.Adaptors.NPM)

      if prev_adapter do
        Application.put_env(:tesla, :adapter, prev_adapter)
      else
        Application.delete_env(:tesla, :adapter)
      end
    end)

    %{
      bypass: bypass,
      tarball_url: "http://localhost:#{bypass.port}/pkg/-/some-2.1.0.tgz"
    }
  end

  describe "icon_hashes/1" do
    test "with nil URL returns all-nil tuple and makes no HTTP call" do
      # No Bypass.expect — if the implementation did fetch, Bypass would
      # raise from its on_exit verification because no handler matched.
      assert {nil, nil, nil, nil} = Tarball.icon_hashes(nil)
    end

    test "returns 4-tuple of {ext, sha} for both icons when present", %{
      bypass: bypass,
      tarball_url: tarball_url
    } do
      square = "SQUARE_PNG_BYTES"
      rectangle = "RECT_PNG_BYTES"

      tarball =
        build_tarball([
          {"package/package.json", "{}"},
          {"package/assets/square.png", square},
          {"package/assets/rectangle.png", rectangle}
        ])

      Bypass.expect(bypass, "GET", "/pkg/-/some-2.1.0.tgz", fn conn ->
        Plug.Conn.resp(conn, 200, tarball)
      end)

      assert {"png", sq_sha, "png", rect_sha} = Tarball.icon_hashes(tarball_url)
      assert sq_sha == :crypto.hash(:sha256, square)
      assert rect_sha == :crypto.hash(:sha256, rectangle)
    end

    test "returns all-nil tuple when the tarball lacks matching icon paths",
         %{bypass: bypass, tarball_url: tarball_url} do
      tarball =
        build_tarball([
          {"package/index.js", "// no icons"},
          {"package/README.md", "hi"}
        ])

      Bypass.expect(bypass, "GET", "/pkg/-/some-2.1.0.tgz", fn conn ->
        Plug.Conn.resp(conn, 200, tarball)
      end)

      assert {nil, nil, nil, nil} = Tarball.icon_hashes(tarball_url)
    end

    test "returns all-nil tuple on 5xx", %{
      bypass: bypass,
      tarball_url: tarball_url
    } do
      Bypass.expect(bypass, "GET", "/pkg/-/some-2.1.0.tgz", fn conn ->
        Plug.Conn.resp(conn, 500, "")
      end)

      assert {nil, nil, nil, nil} = Tarball.icon_hashes(tarball_url)
    end

    test "returns all-nil tuple on connection refused", %{
      bypass: bypass,
      tarball_url: tarball_url
    } do
      Bypass.down(bypass)
      assert {nil, nil, nil, nil} = Tarball.icon_hashes(tarball_url)
    end
  end

  describe "fetch_icon/2" do
    test "returns {:ok, %{data: bytes, ext: ext}} on happy path", %{
      bypass: bypass,
      tarball_url: tarball_url
    } do
      tarball =
        build_tarball([
          {"package/assets/square.png", "PNG_PAYLOAD"},
          {"package/assets/rectangle.svg", "<svg/>"}
        ])

      Bypass.expect(bypass, "GET", "/pkg/-/some-2.1.0.tgz", fn conn ->
        Plug.Conn.resp(conn, 200, tarball)
      end)

      assert {:ok, %{data: "PNG_PAYLOAD", ext: "png"}} =
               Tarball.fetch_icon(tarball_url, :square)
    end

    test "returns {:error, :not_found} when the tarball lacks the icon", %{
      bypass: bypass,
      tarball_url: tarball_url
    } do
      tarball = build_tarball([{"package/index.js", "// nothing"}])

      Bypass.expect(bypass, "GET", "/pkg/-/some-2.1.0.tgz", fn conn ->
        Plug.Conn.resp(conn, 200, tarball)
      end)

      assert {:error, :not_found} = Tarball.fetch_icon(tarball_url, :square)
    end

    test "returns {:error, _} on tarball 5xx", %{
      bypass: bypass,
      tarball_url: tarball_url
    } do
      Bypass.expect(bypass, "GET", "/pkg/-/some-2.1.0.tgz", fn conn ->
        Plug.Conn.resp(conn, 502, "")
      end)

      assert {:error, _} = Tarball.fetch_icon(tarball_url, :square)
    end

    test "returns {:error, _} on malformed gzip body", %{
      bypass: bypass,
      tarball_url: tarball_url
    } do
      Bypass.expect(bypass, "GET", "/pkg/-/some-2.1.0.tgz", fn conn ->
        Plug.Conn.resp(conn, 200, "this is definitely not a gzipped tar")
      end)

      assert {:error, _} = Tarball.fetch_icon(tarball_url, :square)
    end
  end
end
