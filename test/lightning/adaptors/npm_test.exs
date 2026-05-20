defmodule Lightning.Adaptors.NPMTest do
  use ExUnit.Case, async: false

  alias Lightning.Adaptors.NPM

  @package "@openfn/language-http"
  @latest_version "2.1.0"

  # Three Bypass servers: one for the npm registry, one for jsDelivr,
  # one for raw.githubusercontent.com. Per-test config installs all three
  # URLs onto the strategy_opts block.
  setup do
    registry = Bypass.open()
    jsdelivr = Bypass.open()
    github = Bypass.open()

    Application.put_env(:lightning, Lightning.Adaptors.NPM,
      registry_url: "http://localhost:#{registry.port}",
      jsdelivr_url: "http://localhost:#{jsdelivr.port}",
      github_url: "http://localhost:#{github.port}",
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

    %{registry: registry, jsdelivr: jsdelivr, github: github}
  end

  describe "fetch_adaptor/1" do
    test "decodes a packument into the icon-free adaptor_record shape", %{
      registry: registry,
      jsdelivr: jsdelivr
    } do
      schema = %{"type" => "object", "properties" => %{"baseUrl" => %{}}}
      schema_bytes = Jason.encode!(schema)
      packument = build_packument()

      Bypass.expect(registry, "GET", "/" <> @package, fn conn ->
        json_resp(conn, 200, packument)
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
               schema_data: ^schema_bytes,
               schema_sha256: ^expected_schema_sha
             } = record

      refute Map.has_key?(record, :icon_square_ext),
             "fetch_adaptor/1 no longer carries icon fields — the Scheduler joins them"

      refute Map.has_key?(record, :icon_rectangle_ext)
      refute Map.has_key?(record, :icon_square_sha256)
      refute Map.has_key?(record, :icon_rectangle_sha256)

      refute Map.has_key?(record, :source),
             "strategy must not stamp :source — the Store owns that field"

      assert length(record.versions) == 2

      latest = Enum.find(record.versions, &(&1.version == @latest_version))

      assert %{
               integrity: "sha512-abc",
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
      jsdelivr: jsdelivr
    } do
      packument = build_packument()

      Bypass.expect(registry, "GET", "/" <> @package, fn conn ->
        json_resp(conn, 200, packument)
      end)

      Bypass.expect(jsdelivr, fn conn ->
        Plug.Conn.resp(conn, 500, "")
      end)

      {:ok, record} = NPM.fetch_adaptor(@package)

      assert record.schema_data == nil
      assert record.schema_sha256 == nil
      assert record.name == @package
      assert record.latest_version == @latest_version
    end
  end

  describe "fetch_icon/2" do
    test "delegates to NPM.GitHub for raw icon bytes", %{github: github} do
      Bypass.expect(
        github,
        "GET",
        "/OpenFn/adaptors/main/packages/http/assets/square.png",
        fn conn -> Plug.Conn.resp(conn, 200, "PNG_PAYLOAD") end
      )

      assert {:ok, %{data: "PNG_PAYLOAD", ext: "png"}} =
               NPM.fetch_icon(@package, :square)
    end

    test "returns {:error, :not_found} when both png and svg 404", %{
      github: github
    } do
      Bypass.expect(github, fn conn -> Plug.Conn.resp(conn, 404, "") end)

      assert {:error, :not_found} =
               NPM.fetch_icon("@openfn/language-missing", :square)
    end

    test "surfaces transport failure as {:error, _}", %{github: github} do
      Bypass.down(github)

      assert {:error, _reason} = NPM.fetch_icon(@package, :square)
    end
  end

  describe "fetch_icons/1" do
    test "lists adaptors then fans out to GitHub raw fetches", %{
      registry: registry,
      github: github
    } do
      Bypass.expect(registry, "GET", "/-/v1/search", fn conn ->
        body = %{
          "objects" => [
            %{
              "package" => %{
                "name" => "@openfn/language-http",
                "version" => "2.1.0"
              }
            },
            %{
              "package" => %{
                "name" => "@openfn/language-salesforce",
                "version" => "4.6.3"
              }
            }
          ]
        }

        json_resp(conn, 200, body)
      end)

      Bypass.expect(github, fn conn ->
        case conn.request_path do
          "/OpenFn/adaptors/main/packages/http/assets/square.png" ->
            Plug.Conn.resp(conn, 200, "HTTP_SQ")

          "/OpenFn/adaptors/main/packages/salesforce/assets/square.png" ->
            Plug.Conn.resp(conn, 200, "SF_SQ")

          _ ->
            Plug.Conn.resp(conn, 404, "")
        end
      end)

      {:ok, icons} = NPM.fetch_icons([])

      assert %{
               "@openfn/language-http" => %{
                 square: %{data: "HTTP_SQ", ext: "png"}
               },
               "@openfn/language-salesforce" => %{
                 square: %{data: "SF_SQ", ext: "png"}
               }
             } = icons

      assert icons["@openfn/language-http"].square.sha256 ==
               :crypto.hash(:sha256, "HTTP_SQ")
    end

    test "surfaces list_adaptors errors as {:error, _}", %{registry: registry} do
      Bypass.expect(registry, "GET", "/-/v1/search", fn conn ->
        Plug.Conn.resp(conn, 503, "")
      end)

      assert {:error, _} = NPM.fetch_icons([])
    end
  end

  # ==================== Helpers ====================

  defp build_packument do
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
            "unpackedSize" => 5_000
          }
        },
        @latest_version => %{
          "dependencies" => %{"axios" => "^1.5.0"},
          "peerDependencies" => %{"@openfn/language-common" => "^2.0.0"},
          "dist" => %{
            "integrity" => "sha512-abc",
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
