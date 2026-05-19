defmodule Lightning.Adaptors.NPM.GitHubTest do
  use ExUnit.Case, async: false

  alias Lightning.Adaptors.NPM.GitHub

  setup do
    bypass = Bypass.open()

    Application.put_env(:lightning, Lightning.Adaptors.NPM,
      github_url: "http://localhost:#{bypass.port}",
      github_ref: "main",
      http_timeout: 1_000
    )

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

    %{bypass: bypass}
  end

  describe "fetch_one/2" do
    test "returns png bytes on a happy-path 200", %{bypass: bypass} do
      Bypass.expect(
        bypass,
        "GET",
        "/OpenFn/adaptors/main/packages/http/assets/square.png",
        fn conn -> Plug.Conn.resp(conn, 200, "SQUARE_PNG_BYTES") end
      )

      assert {:ok, %{data: "SQUARE_PNG_BYTES", ext: "png"}} =
               GitHub.fetch_one("@openfn/language-http", :square)
    end

    test "falls back to svg when png is missing", %{bypass: bypass} do
      Bypass.expect(bypass, fn conn ->
        case conn.request_path do
          "/OpenFn/adaptors/main/packages/http/assets/rectangle.png" ->
            Plug.Conn.resp(conn, 404, "")

          "/OpenFn/adaptors/main/packages/http/assets/rectangle.svg" ->
            Plug.Conn.resp(conn, 200, "<svg/>")

          path ->
            raise "unexpected path: #{path}"
        end
      end)

      assert {:ok, %{data: "<svg/>", ext: "svg"}} =
               GitHub.fetch_one("@openfn/language-http", :rectangle)
    end

    test "returns {:error, :not_found} when both exts 404", %{bypass: bypass} do
      Bypass.expect(bypass, fn conn -> Plug.Conn.resp(conn, 404, "") end)

      assert {:error, :not_found} =
               GitHub.fetch_one("@openfn/language-missing", :square)
    end

    test "surfaces 5xx as {:error, {:http_status, status}}", %{bypass: bypass} do
      Bypass.expect(bypass, fn conn -> Plug.Conn.resp(conn, 503, "") end)

      assert {:error, {:http_status, 503}} =
               GitHub.fetch_one("@openfn/language-http", :square)
    end

    test "surfaces network failure as {:error, _}", %{bypass: bypass} do
      Bypass.down(bypass)

      assert {:error, _reason} =
               GitHub.fetch_one("@openfn/language-http", :square)
    end

    test "surfaces :http_timeout expiry as {:error, _}", %{bypass: bypass} do
      Bypass.expect(bypass, fn conn ->
        Bypass.pass(bypass)
        Process.sleep(1_500)
        Plug.Conn.resp(conn, 200, "should not arrive")
      end)

      assert {:error, _reason} =
               GitHub.fetch_one("@openfn/language-http", :square)
    end

    test "strips the @openfn/language- prefix from the URL path", %{
      bypass: bypass
    } do
      Bypass.expect(
        bypass,
        "GET",
        "/OpenFn/adaptors/main/packages/salesforce/assets/square.png",
        fn conn -> Plug.Conn.resp(conn, 200, "OK") end
      )

      assert {:ok, %{ext: "png"}} =
               GitHub.fetch_one("@openfn/language-salesforce", :square)
    end

    test "honours the configured :github_ref", %{bypass: bypass} do
      Application.put_env(:lightning, Lightning.Adaptors.NPM,
        github_url: "http://localhost:#{bypass.port}",
        github_ref: "v2",
        http_timeout: 1_000
      )

      Bypass.expect(
        bypass,
        "GET",
        "/OpenFn/adaptors/v2/packages/http/assets/square.png",
        fn conn -> Plug.Conn.resp(conn, 200, "REF_BYTES") end
      )

      assert {:ok, %{data: "REF_BYTES"}} =
               GitHub.fetch_one("@openfn/language-http", :square)
    end
  end

  describe "fetch_all/2" do
    test "returns an entry per package per shape including sha256", %{
      bypass: bypass
    } do
      Bypass.expect(bypass, fn conn ->
        case conn.request_path do
          "/OpenFn/adaptors/main/packages/http/assets/square.png" ->
            Plug.Conn.resp(conn, 200, "HTTP_SQ")

          "/OpenFn/adaptors/main/packages/http/assets/rectangle.png" ->
            Plug.Conn.resp(conn, 200, "HTTP_RECT")

          "/OpenFn/adaptors/main/packages/salesforce/assets/square.png" ->
            Plug.Conn.resp(conn, 200, "SF_SQ")

          "/OpenFn/adaptors/main/packages/salesforce/assets/rectangle.png" ->
            Plug.Conn.resp(conn, 200, "SF_RECT")

          _ ->
            Plug.Conn.resp(conn, 404, "")
        end
      end)

      {:ok, map} =
        GitHub.fetch_all(
          [
            "@openfn/language-http",
            "@openfn/language-salesforce"
          ],
          %{}
        )

      assert %{
               "@openfn/language-http" => %{
                 square: %{data: "HTTP_SQ", ext: "png", sha256: http_sq_sha},
                 rectangle: %{data: "HTTP_RECT", ext: "png"}
               },
               "@openfn/language-salesforce" => %{
                 square: %{data: "SF_SQ", ext: "png"},
                 rectangle: %{data: "SF_RECT", ext: "png"}
               }
             } = map

      assert http_sq_sha == :crypto.hash(:sha256, "HTTP_SQ")
    end

    test "absent packages and missing shapes are simply absent from the map",
         %{bypass: bypass} do
      Bypass.expect(bypass, fn conn ->
        case conn.request_path do
          "/OpenFn/adaptors/main/packages/http/assets/square.png" ->
            Plug.Conn.resp(conn, 200, "ONLY_SQ")

          _ ->
            Plug.Conn.resp(conn, 404, "")
        end
      end)

      {:ok, map} =
        GitHub.fetch_all(
          [
            "@openfn/language-http",
            "@openfn/language-missing"
          ],
          %{}
        )

      assert Map.keys(map) == ["@openfn/language-http"]
      assert Map.keys(map["@openfn/language-http"]) == [:square]
    end

    test "returns {:ok, %{}} when the upstream is unreachable", %{
      bypass: bypass
    } do
      Bypass.down(bypass)

      assert {:ok, map} =
               GitHub.fetch_all(
                 [
                   "@openfn/language-http",
                   "@openfn/language-salesforce"
                 ],
                 %{}
               )

      assert map == %{}
    end

    test "sends If-None-Match when a prior etag is supplied", %{bypass: bypass} do
      etag = ~s(W/"abc")

      Bypass.expect(
        bypass,
        "GET",
        "/OpenFn/adaptors/main/packages/http/assets/square.png",
        fn conn ->
          assert Plug.Conn.get_req_header(conn, "if-none-match") == [etag]
          Plug.Conn.resp(conn, 304, "")
        end
      )

      Bypass.stub(
        bypass,
        "GET",
        "/OpenFn/adaptors/main/packages/http/assets/rectangle.png",
        fn conn ->
          Plug.Conn.resp(conn, 404, "")
        end
      )

      Bypass.stub(
        bypass,
        "GET",
        "/OpenFn/adaptors/main/packages/http/assets/rectangle.svg",
        fn conn ->
          Plug.Conn.resp(conn, 404, "")
        end
      )

      {:ok, map} =
        GitHub.fetch_all(
          ["@openfn/language-http"],
          %{"@openfn/language-http" => %{square: etag}}
        )

      assert get_in(map, ["@openfn/language-http", :square]) == :not_modified
    end

    test "sends no If-None-Match when no prior etag", %{bypass: bypass} do
      Bypass.expect(
        bypass,
        "GET",
        "/OpenFn/adaptors/main/packages/http/assets/square.png",
        fn conn ->
          assert Plug.Conn.get_req_header(conn, "if-none-match") == []

          conn
          |> Plug.Conn.put_resp_header("etag", "test-etag-abc")
          |> Plug.Conn.resp(200, "SQ_BYTES")
        end
      )

      Bypass.stub(
        bypass,
        "GET",
        "/OpenFn/adaptors/main/packages/http/assets/rectangle.png",
        fn conn ->
          Plug.Conn.resp(conn, 404, "")
        end
      )

      Bypass.stub(
        bypass,
        "GET",
        "/OpenFn/adaptors/main/packages/http/assets/rectangle.svg",
        fn conn ->
          Plug.Conn.resp(conn, 404, "")
        end
      )

      {:ok, map} = GitHub.fetch_all(["@openfn/language-http"], %{})

      assert %{
               data: "SQ_BYTES",
               ext: "png",
               etag: "test-etag-abc"
             } = get_in(map, ["@openfn/language-http", :square])
    end

    test "304 short-circuits with the :not_modified sentinel in the slot", %{
      bypass: bypass
    } do
      etag = ~s("xyz")

      Bypass.expect(
        bypass,
        "GET",
        "/OpenFn/adaptors/main/packages/http/assets/square.png",
        fn conn ->
          assert Plug.Conn.get_req_header(conn, "if-none-match") == [etag]
          Plug.Conn.resp(conn, 304, "")
        end
      )

      Bypass.stub(
        bypass,
        "GET",
        "/OpenFn/adaptors/main/packages/http/assets/rectangle.png",
        fn conn ->
          Plug.Conn.resp(conn, 404, "")
        end
      )

      Bypass.stub(
        bypass,
        "GET",
        "/OpenFn/adaptors/main/packages/http/assets/rectangle.svg",
        fn conn ->
          Plug.Conn.resp(conn, 404, "")
        end
      )

      {:ok, map} =
        GitHub.fetch_all(
          ["@openfn/language-http"],
          %{"@openfn/language-http" => %{square: etag}}
        )

      # explicit sentinel — distinct from "absent" (which would mean upstream
      # had no such shape at all).
      assert map["@openfn/language-http"][:square] == :not_modified
    end

    test "200 with a new etag overrides the prior", %{bypass: bypass} do
      prior = ~s("old")
      fresh = ~s("new")

      Bypass.expect(
        bypass,
        "GET",
        "/OpenFn/adaptors/main/packages/http/assets/square.png",
        fn conn ->
          assert Plug.Conn.get_req_header(conn, "if-none-match") == [prior]

          conn
          |> Plug.Conn.put_resp_header("etag", fresh)
          |> Plug.Conn.resp(200, "FRESH")
        end
      )

      Bypass.stub(
        bypass,
        "GET",
        "/OpenFn/adaptors/main/packages/http/assets/rectangle.png",
        fn conn ->
          Plug.Conn.resp(conn, 404, "")
        end
      )

      Bypass.stub(
        bypass,
        "GET",
        "/OpenFn/adaptors/main/packages/http/assets/rectangle.svg",
        fn conn ->
          Plug.Conn.resp(conn, 404, "")
        end
      )

      {:ok, map} =
        GitHub.fetch_all(
          ["@openfn/language-http"],
          %{"@openfn/language-http" => %{square: prior}}
        )

      assert %{data: "FRESH", ext: "png", etag: ^fresh} =
               map["@openfn/language-http"][:square]
    end
  end
end
