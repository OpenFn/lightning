defmodule Lightning.Adaptors.NPMTest do
  use ExUnit.Case, async: false

  import Lightning.Adaptors.NPMTestHelpers, only: [build_tarball: 1]

  alias Lightning.Adaptors.NPM

  @package "@openfn/language-http"
  @latest_version "2.1.0"

  # Two Bypass servers: one stands in for npm registry (which also hosts
  # the per-package tarball under the same hostname in reality — so the
  # packument's `dist.tarball` field points at the same Bypass port), and
  # one for jsDelivr. Embedding the registry Bypass port into the
  # packument's tarball URL means we don't need a third Bypass instance
  # just for the tarball CDN.
  setup do
    registry = Bypass.open()
    jsdelivr = Bypass.open()

    Application.put_env(:lightning, Lightning.Adaptors.NPM,
      registry_url: "http://localhost:#{registry.port}",
      jsdelivr_url: "http://localhost:#{jsdelivr.port}",
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

    %{
      registry: registry,
      jsdelivr: jsdelivr,
      tarball_path: "/#{@package}/-/language-http-#{@latest_version}.tgz",
      tarball_url:
        "http://localhost:#{registry.port}/#{@package}/-/language-http-#{@latest_version}.tgz"
    }
  end

  describe "fetch_adaptor/1" do
    test "decodes a packument into the full adaptor_record shape", %{
      registry: registry,
      jsdelivr: jsdelivr,
      tarball_path: tarball_path,
      tarball_url: tarball_url
    } do
      schema = %{"type" => "object", "properties" => %{"baseUrl" => %{}}}
      schema_bytes = Jason.encode!(schema)

      tarball =
        build_tarball([
          {"package/package.json", "{}"},
          {"package/assets/square.png", "SQ_PNG_BYTES"},
          {"package/assets/rectangle.png", "RECT_PNG_BYTES"}
        ])

      packument = build_packument(tarball_url)

      Bypass.expect(registry, "GET", "/" <> @package, fn conn ->
        json_resp(conn, 200, packument)
      end)

      Bypass.expect(registry, "GET", tarball_path, fn conn ->
        Plug.Conn.resp(conn, 200, tarball)
      end)

      Bypass.expect(
        jsdelivr,
        "GET",
        "/npm/#{@package}@#{@latest_version}/configuration-schema.json",
        fn conn -> Plug.Conn.resp(conn, 200, schema_bytes) end
      )

      {:ok, record} = NPM.fetch_adaptor(@package)

      expected_schema_sha =
        :sha256 |> :crypto.hash(schema_bytes) |> Base.encode16(case: :lower)

      assert %{
               name: @package,
               description: "HTTP adaptor",
               homepage: "https://docs.openfn.org/adaptors/http",
               repository: "git+https://github.com/OpenFn/adaptors.git",
               license: "LGPL-3.0",
               latest_version: @latest_version,
               deprecated: false,
               schema_data: ^schema,
               schema_sha256: ^expected_schema_sha,
               icon_square_ext: "png",
               icon_rectangle_ext: "png"
             } = record

      assert record.icon_square_sha256 == :crypto.hash(:sha256, "SQ_PNG_BYTES")

      assert record.icon_rectangle_sha256 ==
               :crypto.hash(:sha256, "RECT_PNG_BYTES")

      refute Map.has_key?(record, :source),
             "strategy must not stamp :source — the Store owns that field"

      assert length(record.versions) == 2

      latest = Enum.find(record.versions, &(&1.version == @latest_version))

      assert %{
               integrity: "sha512-abc",
               tarball_url: ^tarball_url,
               size_bytes: 12_345,
               dependencies: %{"axios" => "^1.5.0"},
               peer_dependencies: %{"@openfn/language-common" => "^2.0.0"},
               deprecated: false
             } = latest

      assert %DateTime{} = latest.published_at
      assert DateTime.to_iso8601(latest.published_at) =~ "2024-06-01"

      old = Enum.find(record.versions, &(&1.version == "1.0.0"))
      assert old.integrity == "sha512-old"
      assert old.dependencies == %{}
      assert old.deprecated == true
    end

    test "degrades to nil schema when jsDelivr returns 5xx", %{
      registry: registry,
      jsdelivr: jsdelivr,
      tarball_path: tarball_path,
      tarball_url: tarball_url
    } do
      packument = build_packument(tarball_url)
      tarball = build_tarball([{"package/package.json", "{}"}])

      Bypass.expect(registry, "GET", "/" <> @package, fn conn ->
        json_resp(conn, 200, packument)
      end)

      Bypass.expect(registry, "GET", tarball_path, fn conn ->
        Plug.Conn.resp(conn, 200, tarball)
      end)

      Bypass.expect(jsdelivr, fn conn ->
        Plug.Conn.resp(conn, 500, "")
      end)

      {:ok, record} = NPM.fetch_adaptor(@package)

      assert record.schema_data == nil
      assert record.schema_sha256 == nil
      # Other fields still present
      assert record.name == @package
      assert record.latest_version == @latest_version
    end

    test "leaves icon fields nil when tarball fetch fails", %{
      registry: registry,
      jsdelivr: jsdelivr,
      tarball_path: tarball_path,
      tarball_url: tarball_url
    } do
      packument = build_packument(tarball_url)
      schema_bytes = Jason.encode!(%{"type" => "object"})

      Bypass.expect(registry, "GET", "/" <> @package, fn conn ->
        json_resp(conn, 200, packument)
      end)

      Bypass.expect(registry, "GET", tarball_path, fn conn ->
        Plug.Conn.resp(conn, 503, "")
      end)

      Bypass.expect(
        jsdelivr,
        "GET",
        "/npm/#{@package}@#{@latest_version}/configuration-schema.json",
        fn conn -> Plug.Conn.resp(conn, 200, schema_bytes) end
      )

      {:ok, record} = NPM.fetch_adaptor(@package)

      assert record.icon_square_ext == nil
      assert record.icon_square_sha256 == nil
      assert record.icon_rectangle_ext == nil
      assert record.icon_rectangle_sha256 == nil
      # Other fields still present
      assert record.schema_data != nil
      assert record.latest_version == @latest_version
    end
  end

  describe "fetch_icon/2" do
    test "returns icon bytes + ext from the latest version's tarball", %{
      registry: registry,
      tarball_path: tarball_path,
      tarball_url: tarball_url
    } do
      packument = build_packument(tarball_url)

      tarball =
        build_tarball([
          {"package/assets/square.png", "PNG_PAYLOAD"},
          {"package/assets/rectangle.svg", "<svg/>"}
        ])

      Bypass.expect(registry, "GET", "/" <> @package, fn conn ->
        json_resp(conn, 200, packument)
      end)

      Bypass.expect(registry, "GET", tarball_path, fn conn ->
        Plug.Conn.resp(conn, 200, tarball)
      end)

      assert {:ok, %{data: "PNG_PAYLOAD", ext: "png"}} =
               NPM.fetch_icon(@package, :square)
    end

    test "returns {:error, :not_found} when the packument is 404", %{
      registry: registry
    } do
      Bypass.expect(registry, "GET", "/@openfn/language-missing", fn conn ->
        Plug.Conn.resp(conn, 404, "")
      end)

      assert {:error, :not_found} =
               NPM.fetch_icon("@openfn/language-missing", :square)
    end

    test "surfaces tarball 5xx as {:error, _}", %{
      registry: registry,
      tarball_path: tarball_path,
      tarball_url: tarball_url
    } do
      packument = build_packument(tarball_url)

      Bypass.expect(registry, "GET", "/" <> @package, fn conn ->
        json_resp(conn, 200, packument)
      end)

      Bypass.expect(registry, "GET", tarball_path, fn conn ->
        Plug.Conn.resp(conn, 502, "")
      end)

      assert {:error, _} = NPM.fetch_icon(@package, :square)
    end
  end

  # ==================== Helpers ====================

  defp build_packument(tarball_url) do
    %{
      "name" => @package,
      "description" => "HTTP adaptor",
      "homepage" => "https://docs.openfn.org/adaptors/http",
      "repository" => %{"url" => "git+https://github.com/OpenFn/adaptors.git"},
      "license" => "LGPL-3.0",
      "dist-tags" => %{"latest" => @latest_version},
      "time" => %{
        "1.0.0" => "2023-01-01T00:00:00.000Z",
        "2.1.0" => "2024-06-01T12:00:00.000Z"
      },
      "versions" => %{
        "1.0.0" => %{
          "dependencies" => %{},
          "peerDependencies" => %{},
          "deprecated" => "please upgrade",
          "dist" => %{
            "integrity" => "sha512-old",
            "tarball" =>
              String.replace(
                tarball_url,
                "language-http-#{@latest_version}.tgz",
                "language-http-1.0.0.tgz"
              ),
            "unpackedSize" => 5_000
          }
        },
        @latest_version => %{
          "dependencies" => %{"axios" => "^1.5.0"},
          "peerDependencies" => %{"@openfn/language-common" => "^2.0.0"},
          "dist" => %{
            "integrity" => "sha512-abc",
            "tarball" => tarball_url,
            "unpackedSize" => 12_345
          }
        }
      }
    }
  end

  defp json_resp(conn, status, body) do
    conn
    |> Plug.Conn.put_resp_content_type("application/json")
    |> Plug.Conn.resp(status, Jason.encode!(body))
  end
end
