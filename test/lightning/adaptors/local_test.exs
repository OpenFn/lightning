defmodule Lightning.Adaptors.LocalTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias Lightning.Adaptors.Local

  setup do
    root =
      Path.join(
        System.tmp_dir!(),
        "lightning_adaptors_local_test_#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(Path.join(root, "packages"))

    original = Application.get_env(:lightning, Local, :__unset__)
    Application.put_env(:lightning, Local, path: root)

    on_exit(fn ->
      case original do
        :__unset__ -> Application.delete_env(:lightning, Local)
        value -> Application.put_env(:lightning, Local, value)
      end

      File.rm_rf!(root)
    end)

    {:ok, root: root}
  end

  describe "list_adaptors/0" do
    test "returns {:ok, []} when there are no package directories" do
      assert Local.list_adaptors() == {:ok, []}
    end

    test "returns name + latest_version for each package", %{root: root} do
      write_package!(root, "language-http", "@openfn/language-http", "2.1.0")

      write_package!(
        root,
        "language-salesforce",
        "@openfn/language-salesforce",
        "4.6.3"
      )

      {:ok, listing} = Local.list_adaptors()

      assert Enum.sort_by(listing, & &1.name) == [
               %{name: "@openfn/language-http", latest_version: "2.1.0"},
               %{name: "@openfn/language-salesforce", latest_version: "4.6.3"}
             ]
    end

    test "collapses multiple directories sharing a name into one record with the highest semver as latest_version",
         %{root: root} do
      write_package!(root, "http-1", "@openfn/language-http", "1.0.0")
      write_package!(root, "http-2", "@openfn/language-http", "2.3.4")
      write_package!(root, "http-3", "@openfn/language-http", "2.3.1")

      assert {:ok, [%{name: "@openfn/language-http", latest_version: "2.3.4"}]} =
               Local.list_adaptors()
    end

    test "skips a directory with a missing package.json and logs a warning",
         %{root: root} do
      write_package!(root, "good", "@openfn/language-good", "1.0.0")
      File.mkdir_p!(Path.join([root, "packages", "broken"]))

      {result, log} = with_log(fn -> Local.list_adaptors() end)

      assert {:ok, [%{name: "@openfn/language-good"}]} = result
      assert log =~ "skipping"
      assert log =~ "broken"
    end

    test "skips a directory with unparseable JSON and logs a warning",
         %{root: root} do
      bad_dir = Path.join([root, "packages", "junk"])
      File.mkdir_p!(bad_dir)
      File.write!(Path.join(bad_dir, "package.json"), "{not json")

      {result, log} = with_log(fn -> Local.list_adaptors() end)

      assert {:ok, []} = result
      assert log =~ "skipping"
      assert log =~ "junk"
    end

    test "skips package.json that has no name or version", %{root: root} do
      dir = Path.join([root, "packages", "incomplete"])
      File.mkdir_p!(dir)

      File.write!(
        Path.join(dir, "package.json"),
        Jason.encode!(%{"name" => "x"})
      )

      {result, _log} = with_log(fn -> Local.list_adaptors() end)

      assert {:ok, []} = result
    end

    test "returns {:error, :no_repo_path} when :path is unset" do
      Application.delete_env(:lightning, Local)

      assert capture_log(fn ->
               assert Local.list_adaptors() == {:error, :no_repo_path}
             end) =~ "not configured"
    end
  end

  describe "fetch_adaptor/1" do
    test "decodes a realistic on-disk package into the full adaptor_record shape",
         %{root: root} do
      pkg = %{
        "name" => "@openfn/language-http",
        "version" => "2.1.0",
        "description" => "HTTP adaptor",
        "homepage" => "https://docs.openfn.org/adaptors/http",
        "repository" => %{"url" => "git+https://github.com/OpenFn/adaptors.git"},
        "license" => "LGPL-3.0",
        "dependencies" => %{"axios" => "^1.5.0"},
        "peerDependencies" => %{"@openfn/language-common" => "^2.0.0"}
      }

      schema = %{"type" => "object", "properties" => %{"baseUrl" => %{}}}

      dir = write_package_raw!(root, "language-http", pkg)

      File.write!(
        Path.join(dir, "configuration-schema.json"),
        Jason.encode!(schema)
      )

      write_icon!(dir, :square, "png", "square-bytes")
      write_icon!(dir, :rectangle, "svg", "<svg/>")

      {:ok, record} = Local.fetch_adaptor("@openfn/language-http")

      assert record.name == "@openfn/language-http"
      assert record.description == "HTTP adaptor"
      assert record.homepage == "https://docs.openfn.org/adaptors/http"
      assert record.repository == "git+https://github.com/OpenFn/adaptors.git"
      assert record.license == "LGPL-3.0"
      assert record.latest_version == "2.1.0"
      assert record.deprecated == false
      assert record.schema_data == Jason.encode!(schema)

      assert record.schema_sha256 ==
               :crypto.hash(:sha256, Jason.encode!(schema))
               |> Base.encode16(case: :lower)

      refute Map.has_key?(record, :icon_square_ext),
             "fetch_adaptor/1 no longer carries icon fields — the Scheduler joins them"

      refute Map.has_key?(record, :icon_rectangle_ext)
      refute Map.has_key?(record, :icon_square_sha256)
      refute Map.has_key?(record, :icon_rectangle_sha256)

      refute Map.has_key?(record, :source),
             "the strategy must not stamp :source — the Store owns that field"

      assert [version] = record.versions
      assert version.version == "2.1.0"
      assert version.dependencies == %{"axios" => "^1.5.0"}

      assert version.peer_dependencies == %{
               "@openfn/language-common" => "^2.0.0"
             }

      assert version.integrity == nil
      assert version.tarball_url == nil
      assert version.size_bytes == nil
      assert version.published_at == nil
      assert version.deprecated == false
    end

    test "reads schema_data from the latest version's directory specifically",
         %{root: root} do
      old_dir =
        write_package_raw!(root, "http-old", %{
          "name" => "@openfn/language-http",
          "version" => "1.0.0"
        })

      new_dir =
        write_package_raw!(root, "http-new", %{
          "name" => "@openfn/language-http",
          "version" => "2.0.0"
        })

      File.write!(
        Path.join(old_dir, "configuration-schema.json"),
        Jason.encode!(%{"version" => "old"})
      )

      File.write!(
        Path.join(new_dir, "configuration-schema.json"),
        Jason.encode!(%{"version" => "new"})
      )

      {:ok, record} = Local.fetch_adaptor("@openfn/language-http")

      assert record.schema_data == Jason.encode!(%{"version" => "new"})
      assert record.latest_version == "2.0.0"
    end

    test "returns nil-shaped schema fields when files are absent",
         %{root: root} do
      write_package!(root, "bare", "@openfn/language-bare", "1.0.0")

      {:ok, record} = Local.fetch_adaptor("@openfn/language-bare")

      assert record.schema_data == nil
      assert record.schema_sha256 == nil
    end

    test "handles a plain-string repository field", %{root: root} do
      write_package_raw!(root, "p", %{
        "name" => "@openfn/language-p",
        "version" => "1.0.0",
        "repository" => "https://github.com/example/p"
      })

      {:ok, record} = Local.fetch_adaptor("@openfn/language-p")
      assert record.repository == "https://github.com/example/p"
    end

    test "lists every on-disk version in :versions", %{root: root} do
      write_package!(root, "http-1", "@openfn/language-http", "1.0.0")
      write_package!(root, "http-2", "@openfn/language-http", "2.3.4")
      write_package!(root, "http-3", "@openfn/language-http", "2.3.1")

      {:ok, record} = Local.fetch_adaptor("@openfn/language-http")

      versions = Enum.map(record.versions, & &1.version)
      assert versions == ["2.3.4", "2.3.1", "1.0.0"]
    end

    test "returns {:error, :not_found} for an unknown package", %{root: root} do
      write_package!(root, "p", "@openfn/language-p", "1.0.0")

      assert Local.fetch_adaptor("@openfn/language-missing") ==
               {:error, :not_found}
    end
  end

  describe "fetch_icon/2" do
    test "reads an icon from the latest version's assets dir", %{root: root} do
      dir = write_package!(root, "http", "@openfn/language-http", "1.0.0")
      write_icon!(dir, :square, "png", "PNGDATA")

      assert {:ok, %{data: "PNGDATA", ext: "png"}} =
               Local.fetch_icon("@openfn/language-http", :square)
    end

    test "prefers the latest version when multiple version dirs exist",
         %{root: root} do
      old_dir =
        write_package_raw!(root, "http-old", %{
          "name" => "@openfn/language-http",
          "version" => "1.0.0"
        })

      new_dir =
        write_package_raw!(root, "http-new", %{
          "name" => "@openfn/language-http",
          "version" => "2.0.0"
        })

      write_icon!(old_dir, :square, "png", "OLD")
      write_icon!(new_dir, :square, "png", "NEW")

      assert {:ok, %{data: "NEW", ext: "png"}} =
               Local.fetch_icon("@openfn/language-http", :square)
    end

    test "falls back to svg when png is absent", %{root: root} do
      dir = write_package!(root, "p", "@openfn/language-p", "1.0.0")
      write_icon!(dir, :rectangle, "svg", "<svg/>")

      assert {:ok, %{data: "<svg/>", ext: "svg"}} =
               Local.fetch_icon("@openfn/language-p", :rectangle)
    end

    test "returns {:error, :not_found} when no icon variant exists",
         %{root: root} do
      write_package!(root, "p", "@openfn/language-p", "1.0.0")

      assert Local.fetch_icon("@openfn/language-p", :square) ==
               {:error, :not_found}
    end

    test "returns {:error, :not_found} for an unknown package", %{root: root} do
      write_package!(root, "p", "@openfn/language-p", "1.0.0")

      assert Local.fetch_icon("@openfn/language-missing", :square) ==
               {:error, :not_found}
    end
  end

  describe "fetch_icons/1" do
    test "returns an entry per package per shape including sha256",
         %{root: root} do
      http = write_package!(root, "http", "@openfn/language-http", "1.0.0")
      sf = write_package!(root, "sf", "@openfn/language-salesforce", "2.0.0")

      write_icon!(http, :square, "png", "HTTP_SQ")
      write_icon!(http, :rectangle, "svg", "<svg/>")
      write_icon!(sf, :square, "png", "SF_SQ")

      {:ok, map} = Local.fetch_icons([])

      assert %{
               "@openfn/language-http" => %{
                 square: %{data: "HTTP_SQ", ext: "png", sha256: http_sq_sha},
                 rectangle: %{data: "<svg/>", ext: "svg"}
               },
               "@openfn/language-salesforce" => %{
                 square: %{data: "SF_SQ", ext: "png"}
               }
             } = map

      assert http_sq_sha == :crypto.hash(:sha256, "HTTP_SQ")
      refute Map.has_key?(map["@openfn/language-salesforce"], :rectangle)
    end

    test "returns {:ok, %{}} when no packages have icons", %{root: root} do
      write_package!(root, "bare", "@openfn/language-bare", "1.0.0")

      assert {:ok, %{}} = Local.fetch_icons([])
    end

    test "returns {:error, :no_repo_path} when :path is unset" do
      Application.delete_env(:lightning, Local)

      assert capture_log(fn ->
               assert Local.fetch_icons([]) == {:error, :no_repo_path}
             end) =~ "not configured"
    end
  end

  defp write_package!(root, dir_name, name, version) do
    write_package_raw!(root, dir_name, %{"name" => name, "version" => version})
  end

  defp write_package_raw!(root, dir_name, package_json) do
    dir = Path.join([root, "packages", dir_name])
    File.mkdir_p!(dir)
    File.write!(Path.join(dir, "package.json"), Jason.encode!(package_json))
    dir
  end

  defp write_icon!(dir, shape, ext, bytes) do
    assets = Path.join(dir, "assets")
    File.mkdir_p!(assets)
    File.write!(Path.join(assets, "#{shape}.#{ext}"), bytes)
  end
end
