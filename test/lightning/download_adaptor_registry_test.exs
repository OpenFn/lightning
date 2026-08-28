defmodule Lightning.DownloadAdaptorRegistryCacheTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  alias Mix.Tasks.Lightning.DownloadAdaptorRegistryCache

  @package "@openfn/language-http"
  @latest_version "2.1.0"

  # Bypass servers for the npm registry and jsDelivr, installed onto the
  # NPM strategy's own Application key. Matches the setup in
  # test/lightning/adaptors/npm_test.exs.
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

    %{registry: registry, jsdelivr: jsdelivr}
  end

  describe "download_adaptor_registry_cache mix task" do
    @describetag :tmp_dir
    test "does not write file when no adaptors are found", %{
      tmp_dir: tmp_dir,
      registry: registry
    } do
      Bypass.expect(registry, "GET", "/-/v1/search", fn conn ->
        json_resp(conn, 200, %{"objects" => []})
      end)

      file_path = Path.join([tmp_dir, "cache.json"])
      refute File.exists?(file_path)

      capture_io(fn ->
        DownloadAdaptorRegistryCache.run(["--path", file_path])
      end)

      refute File.exists?(file_path)
    end

    test "writes full adaptor records to the specified file", %{
      tmp_dir: tmp_dir,
      registry: registry,
      jsdelivr: jsdelivr
    } do
      Bypass.expect(registry, "GET", "/-/v1/search", fn conn ->
        json_resp(conn, 200, %{
          "objects" => [
            %{"package" => %{"name" => @package, "version" => @latest_version}}
          ]
        })
      end)

      Bypass.expect(registry, "GET", "/" <> @package, fn conn ->
        json_resp(conn, 200, build_packument())
      end)

      Bypass.expect(
        jsdelivr,
        "GET",
        "/npm/#{@package}@#{@latest_version}/configuration-schema.json",
        fn conn -> Plug.Conn.resp(conn, 200, "{}") end
      )

      file_path = Path.join([tmp_dir, "cache.json"])
      refute File.exists?(file_path)

      capture_io(fn ->
        DownloadAdaptorRegistryCache.run(["--path", file_path])
      end)

      assert [record] =
               file_path |> File.read!() |> Jason.decode!(keys: :atoms)

      assert %{
               name: @package,
               source: "npm",
               latest_version: @latest_version,
               versions: [%{version: @latest_version}]
             } = record
    end
  end

  defp build_packument do
    %{
      "name" => @package,
      "description" => "HTTP adaptor",
      "repository" => %{"url" => "git+https://github.com/OpenFn/adaptors.git"},
      "license" => "LGPL-3.0",
      "dist-tags" => %{"latest" => @latest_version},
      "time" => %{@latest_version => "2024-06-01T12:00:00.000Z"},
      "versions" => %{
        @latest_version => %{
          "dependencies" => %{},
          "peerDependencies" => %{},
          "dist" => %{"integrity" => "sha512-abc", "unpackedSize" => 12_345}
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
