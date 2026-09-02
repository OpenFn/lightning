defmodule Mix.Tasks.Lightning.SeedAdaptorsFromFileTest do
  use Lightning.DataCase

  import ExUnit.CaptureIO

  alias Lightning.Adaptors.Catalogue
  alias Mix.Tasks.Lightning.SeedAdaptorsFromFile

  @moduletag :tmp_dir

  defp write_snapshot(tmp_dir, records) do
    path = Path.join(tmp_dir, "snapshot.json")
    File.write!(path, Jason.encode_to_iodata!(records))
    path
  end

  describe "run/1" do
    test "upserts every record in the file into the given source", %{
      tmp_dir: tmp_dir
    } do
      path =
        write_snapshot(tmp_dir, [
          %{
            name: "@openfn/language-http",
            latest_version: "2.1.0",
            versions: [%{version: "2.1.0"}, %{version: "2.0.0"}]
          }
        ])

      capture_io(fn ->
        SeedAdaptorsFromFile.run(["--path", path])
      end)

      assert %{latest_version: "2.1.0"} =
               Catalogue.get_adaptor("@openfn/language-http", :npm)

      assert length(Catalogue.list_versions("@openfn/language-http", :npm)) ==
               2
    end

    test "seeds the :local source when --source local is given", %{
      tmp_dir: tmp_dir
    } do
      path =
        write_snapshot(tmp_dir, [
          %{
            name: "@openfn/language-common",
            latest_version: "1.0.0",
            versions: []
          }
        ])

      capture_io(fn ->
        SeedAdaptorsFromFile.run(["--path", path, "--source", "local"])
      end)

      assert Catalogue.get_adaptor("@openfn/language-common", :npm) == nil

      assert %{source: :local} =
               Catalogue.get_adaptor("@openfn/language-common", :local)
    end

    test "--replace deletes existing rows for the source before seeding", %{
      tmp_dir: tmp_dir
    } do
      insert(:adaptor, name: "@openfn/language-stale", source: :npm)

      path =
        write_snapshot(tmp_dir, [
          %{name: "@openfn/language-http", latest_version: "1.0.0", versions: []}
        ])

      capture_io(fn ->
        SeedAdaptorsFromFile.run(["--path", path, "--replace"])
      end)

      assert Catalogue.get_adaptor("@openfn/language-stale", :npm) == nil
      assert Catalogue.get_adaptor("@openfn/language-http", :npm) != nil
    end

    test "--replace rolls back the delete when a later record fails to upsert",
         %{tmp_dir: tmp_dir} do
      insert(:adaptor, name: "@openfn/language-stale", source: :npm)

      path =
        write_snapshot(tmp_dir, [
          %{
            name: "@openfn/language-http",
            latest_version: "1.0.0",
            versions: []
          },
          # Missing `latest_version`, required by the Adaptor changeset, so
          # this fails inside `upsert_adaptor/1` rather than at normalize.
          %{name: "@openfn/language-broken", versions: []}
        ])

      assert_raise ArgumentError, fn ->
        capture_io(fn ->
          SeedAdaptorsFromFile.run(["--path", path, "--replace"])
        end)
      end

      assert Catalogue.get_adaptor("@openfn/language-stale", :npm) != nil
      assert Catalogue.get_adaptor("@openfn/language-http", :npm) == nil
    end

    test "round-trips a snapshot in the shape the download task emits", %{
      tmp_dir: tmp_dir
    } do
      # Same shape `mix lightning.download_adaptor_registry_cache` writes:
      # an atom-keyed adaptor_record (see Lightning.Adaptors.Strategy) plus
      # :source, run through Jason.encode_to_iodata!/1.
      record = %{
        name: "@openfn/language-http",
        description: "HTTP adaptor",
        homepage: nil,
        repository: "git+https://github.com/OpenFn/adaptors.git",
        license: "LGPL-3.0",
        latest_version: "2.1.0",
        deprecated: false,
        schema_data: nil,
        schema_sha256: nil,
        source: :npm,
        versions: [
          %{
            version: "2.1.0",
            integrity: "sha512-abc",
            tarball_url: "https://example.com/http-2.1.0.tgz",
            size_bytes: 12_345,
            dependencies: %{"axios" => "^1.5.0"},
            peer_dependencies: %{},
            published_at: DateTime.utc_now(),
            deprecated: false
          }
        ]
      }

      path = tmp_dir |> Path.join("snapshot.json")
      File.write!(path, Jason.encode_to_iodata!([record]))

      capture_io(fn ->
        SeedAdaptorsFromFile.run(["--path", path])
      end)

      assert [%{name: "@openfn/language-http", versions: ["2.1.0"]}] =
               Catalogue.catalogue(:npm)
    end
  end
end
