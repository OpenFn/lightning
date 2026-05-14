defmodule Lightning.Adaptors.NPMTest do
  use ExUnit.Case, async: false

  import Mox

  alias Lightning.Adaptors.NPM

  setup :verify_on_exit!

  @registry_base "https://registry.npmjs.org"
  @jsdelivr_base "https://cdn.jsdelivr.net"
  @package "@openfn/language-http"
  @latest_version "2.1.0"
  @tarball_url "#{@registry_base}/#{@package}/-/language-http-#{@latest_version}.tgz"

  describe "list_adaptors/0" do
    test "returns an empty list when the search has no results" do
      expect(Lightning.Tesla.Mock, :call, fn env, _opts ->
        assert env.method == :get
        assert env.url == "#{@registry_base}/-/v1/search"
        assert env.query == [text: "scope:openfn", size: 250]
        {:ok, %Tesla.Env{status: 200, body: %{"objects" => []}}}
      end)

      assert {:ok, []} = NPM.list_adaptors()
    end

    test "returns name + latest_version for each search hit" do
      expect(Lightning.Tesla.Mock, :call, fn _env, _opts ->
        {:ok,
         %Tesla.Env{
           status: 200,
           body: %{
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
         }}
      end)

      {:ok, listing} = NPM.list_adaptors()

      assert Enum.sort_by(listing, & &1.name) == [
               %{name: "@openfn/language-http", latest_version: "2.1.0"},
               %{name: "@openfn/language-salesforce", latest_version: "4.6.3"}
             ]
    end

    test "skips malformed entries that lack name or version" do
      expect(Lightning.Tesla.Mock, :call, fn _env, _opts ->
        {:ok,
         %Tesla.Env{
           status: 200,
           body: %{
             "objects" => [
               %{
                 "package" => %{
                   "name" => "@openfn/language-http",
                   "version" => "1.0.0"
                 }
               },
               %{"package" => %{"name" => "@openfn/no-version"}},
               %{"score" => %{"final" => 0.5}}
             ]
           }
         }}
      end)

      assert {:ok, [%{name: "@openfn/language-http", latest_version: "1.0.0"}]} =
               NPM.list_adaptors()
    end

    test "surfaces 5xx responses as {:error, _}" do
      expect(Lightning.Tesla.Mock, :call, fn _env, _opts ->
        {:ok, %Tesla.Env{status: 503, body: ""}}
      end)

      assert {:error, _} = NPM.list_adaptors()
    end

    test "surfaces nxdomain / timeout as {:error, _}" do
      expect(Lightning.Tesla.Mock, :call, fn _env, _opts ->
        {:error, :nxdomain}
      end)

      assert {:error, :nxdomain} = NPM.list_adaptors()
    end
  end

  describe "fetch_adaptor/1" do
    test "decodes a realistic packument into the full adaptor_record shape" do
      schema = %{"type" => "object", "properties" => %{"baseUrl" => %{}}}
      schema_bytes = Jason.encode!(schema)

      tarball =
        build_tarball([
          {"package/package.json", "{}"},
          {"package/assets/square.png", "SQ_PNG_BYTES"},
          {"package/assets/rectangle.png", "RECT_PNG_BYTES"}
        ])

      packument = build_packument()

      stub(
        Lightning.Tesla.Mock,
        :call,
        &dispatch(&1, &2, packument, schema_bytes, tarball)
      )

      {:ok, record} = NPM.fetch_adaptor(@package)

      assert record.name == @package
      assert record.description == "HTTP adaptor"
      assert record.homepage == "https://docs.openfn.org/adaptors/http"
      assert record.repository == "git+https://github.com/OpenFn/adaptors.git"
      assert record.license == "LGPL-3.0"
      assert record.latest_version == @latest_version
      assert record.deprecated == false
      assert record.schema_data == schema

      assert record.schema_sha256 ==
               :sha256
               |> :crypto.hash(schema_bytes)
               |> Base.encode16(case: :lower)

      assert record.icon_square_ext == "png"
      assert record.icon_square_sha256 == :crypto.hash(:sha256, "SQ_PNG_BYTES")
      assert record.icon_rectangle_ext == "png"

      assert record.icon_rectangle_sha256 ==
               :crypto.hash(:sha256, "RECT_PNG_BYTES")

      refute Map.has_key?(record, :source),
             "strategy must not stamp :source — the Store owns that field"

      assert length(record.versions) == 2

      latest = Enum.find(record.versions, &(&1.version == @latest_version))
      assert latest.integrity == "sha512-abc"
      assert latest.tarball_url == @tarball_url
      assert latest.size_bytes == 12_345
      assert latest.dependencies == %{"axios" => "^1.5.0"}
      assert latest.peer_dependencies == %{"@openfn/language-common" => "^2.0.0"}
      assert %DateTime{} = latest.published_at
      assert DateTime.to_iso8601(latest.published_at) =~ "2024-06-01"
      assert latest.deprecated == false

      old = Enum.find(record.versions, &(&1.version == "1.0.0"))
      assert old.integrity == "sha512-old"
      assert old.dependencies == %{}
      assert old.deprecated == true
    end

    test "returns {:error, :not_found} when the packument is 404" do
      expect(Lightning.Tesla.Mock, :call, fn _env, _opts ->
        {:ok, %Tesla.Env{status: 404, body: ""}}
      end)

      assert {:error, :not_found} =
               NPM.fetch_adaptor("@openfn/language-missing")
    end

    test "surfaces packument 5xx as {:error, _}" do
      expect(Lightning.Tesla.Mock, :call, fn _env, _opts ->
        {:ok, %Tesla.Env{status: 503, body: ""}}
      end)

      assert {:error, _} = NPM.fetch_adaptor(@package)
    end

    test "surfaces packument nxdomain as {:error, _}" do
      expect(Lightning.Tesla.Mock, :call, fn _env, _opts ->
        {:error, :nxdomain}
      end)

      assert {:error, :nxdomain} = NPM.fetch_adaptor(@package)
    end

    test "degrades to nil schema when jsDelivr returns 5xx (no error propagation)" do
      packument = build_packument()
      tarball = build_tarball([{"package/package.json", "{}"}])

      stub(Lightning.Tesla.Mock, :call, fn env, _opts ->
        cond do
          env.url == "#{@registry_base}/#{@package}" ->
            {:ok, %Tesla.Env{status: 200, body: packument}}

          String.starts_with?(env.url, @jsdelivr_base) ->
            {:ok, %Tesla.Env{status: 500, body: ""}}

          env.url == @tarball_url ->
            {:ok, %Tesla.Env{status: 200, body: tarball}}
        end
      end)

      {:ok, record} = NPM.fetch_adaptor(@package)
      assert record.schema_data == nil
      assert record.schema_sha256 == nil
    end

    test "degrades to nil icons when tarball fetch fails" do
      packument = build_packument()
      schema_bytes = Jason.encode!(%{"type" => "object"})

      stub(Lightning.Tesla.Mock, :call, fn env, _opts ->
        cond do
          env.url == "#{@registry_base}/#{@package}" ->
            {:ok, %Tesla.Env{status: 200, body: packument}}

          String.starts_with?(env.url, @jsdelivr_base) ->
            {:ok, %Tesla.Env{status: 200, body: schema_bytes}}

          env.url == @tarball_url ->
            {:error, :timeout}
        end
      end)

      {:ok, record} = NPM.fetch_adaptor(@package)
      assert record.icon_square_ext == nil
      assert record.icon_square_sha256 == nil
      assert record.icon_rectangle_ext == nil
      assert record.icon_rectangle_sha256 == nil
    end

    test "leaves icons nil when the tarball does not contain matching files" do
      packument = build_packument()
      schema_bytes = Jason.encode!(%{"type" => "object"})
      tarball = build_tarball([{"package/index.js", "// nothing"}])

      stub(
        Lightning.Tesla.Mock,
        :call,
        &dispatch(&1, &2, packument, schema_bytes, tarball)
      )

      {:ok, record} = NPM.fetch_adaptor(@package)
      assert record.icon_square_ext == nil
      assert record.icon_square_sha256 == nil
    end
  end

  describe "fetch_icon/2" do
    test "returns the bytes and extension from the latest version's tarball" do
      packument = build_packument()

      tarball =
        build_tarball([
          {"package/assets/square.png", "PNG_PAYLOAD"},
          {"package/assets/rectangle.svg", "<svg/>"}
        ])

      stub(Lightning.Tesla.Mock, :call, fn env, _opts ->
        cond do
          env.url == "#{@registry_base}/#{@package}" ->
            {:ok, %Tesla.Env{status: 200, body: packument}}

          env.url == @tarball_url ->
            {:ok, %Tesla.Env{status: 200, body: tarball}}
        end
      end)

      assert {:ok, %{data: "PNG_PAYLOAD", ext: "png"}} =
               NPM.fetch_icon(@package, :square)

      assert {:ok, %{data: "<svg/>", ext: "svg"}} =
               NPM.fetch_icon(@package, :rectangle)
    end

    test "returns {:error, :not_found} when the tarball lacks the requested icon" do
      packument = build_packument()
      tarball = build_tarball([{"package/index.js", "// nothing"}])

      stub(Lightning.Tesla.Mock, :call, fn env, _opts ->
        cond do
          env.url == "#{@registry_base}/#{@package}" ->
            {:ok, %Tesla.Env{status: 200, body: packument}}

          env.url == @tarball_url ->
            {:ok, %Tesla.Env{status: 200, body: tarball}}
        end
      end)

      assert {:error, :not_found} = NPM.fetch_icon(@package, :square)
    end

    test "surfaces packument 404 as {:error, :not_found}" do
      expect(Lightning.Tesla.Mock, :call, fn _env, _opts ->
        {:ok, %Tesla.Env{status: 404, body: ""}}
      end)

      assert {:error, :not_found} =
               NPM.fetch_icon("@openfn/language-missing", :square)
    end

    test "surfaces tarball 5xx as {:error, _}" do
      packument = build_packument()

      stub(Lightning.Tesla.Mock, :call, fn env, _opts ->
        cond do
          env.url == "#{@registry_base}/#{@package}" ->
            {:ok, %Tesla.Env{status: 200, body: packument}}

          env.url == @tarball_url ->
            {:ok, %Tesla.Env{status: 502, body: ""}}
        end
      end)

      assert {:error, _} = NPM.fetch_icon(@package, :square)
    end
  end

  # ==================== Helpers ====================

  defp dispatch(env, _opts, packument, schema_bytes, tarball) do
    cond do
      env.url == "#{@registry_base}/#{@package}" ->
        {:ok, %Tesla.Env{status: 200, body: packument}}

      String.starts_with?(env.url, @jsdelivr_base) ->
        {:ok, %Tesla.Env{status: 200, body: schema_bytes}}

      env.url == @tarball_url ->
        {:ok, %Tesla.Env{status: 200, body: tarball}}
    end
  end

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
            "tarball" =>
              "#{@registry_base}/#{@package}/-/language-http-1.0.0.tgz",
            "unpackedSize" => 5_000
          }
        },
        "2.1.0" => %{
          "dependencies" => %{"axios" => "^1.5.0"},
          "peerDependencies" => %{"@openfn/language-common" => "^2.0.0"},
          "dist" => %{
            "integrity" => "sha512-abc",
            "tarball" => @tarball_url,
            "unpackedSize" => 12_345
          }
        }
      }
    }
  end

  defp build_tarball(entries) do
    tar_path =
      Path.join(
        System.tmp_dir!(),
        "npm_adaptor_test_#{System.unique_integer([:positive])}.tar.gz"
      )

    files =
      Enum.map(entries, fn {name, body} -> {to_charlist(name), body} end)

    :ok = :erl_tar.create(to_charlist(tar_path), files, [:compressed])
    bytes = File.read!(tar_path)
    File.rm!(tar_path)
    bytes
  end
end
