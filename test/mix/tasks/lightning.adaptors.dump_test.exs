defmodule Mix.Tasks.Lightning.Adaptors.DumpTest do
  use Lightning.DataCase

  import ExUnit.CaptureIO

  alias Lightning.Adaptors.Catalogue
  alias Mix.Tasks.Lightning.Adaptors.Dump

  @moduletag :tmp_dir

  defp http_record(source) do
    %{
      name: "@openfn/language-http",
      source: source,
      description: "HTTP adaptor",
      homepage: "https://openfn.org",
      repository: "git+https://github.com/OpenFn/adaptors.git",
      license: "LGPL-3.0",
      latest_version: "2.1.0",
      deprecated: false,
      schema_data: ~s({"type":"object"}),
      schema_sha256: "sha256-schema-http",
      versions: [
        %{
          version: "2.0.0",
          integrity: "sha512-two-oh",
          tarball_url: "https://example.com/http-2.0.0.tgz",
          size_bytes: 11_111,
          dependencies: %{"axios" => "^1.4.0"},
          peer_dependencies: %{},
          published_at: ~U[2024-01-01 00:00:00.000000Z],
          deprecated: true
        },
        %{
          version: "2.1.0",
          integrity: "sha512-two-one",
          tarball_url: "https://example.com/http-2.1.0.tgz",
          size_bytes: 12_345,
          dependencies: %{"axios" => "^1.5.0"},
          peer_dependencies: %{"@openfn/language-common" => "^2.0.0"},
          published_at: ~U[2024-06-01 12:00:00.000000Z],
          deprecated: false
        }
      ]
    }
  end

  defp common_record(source) do
    %{
      name: "@openfn/language-common",
      source: source,
      description: "Common helpers",
      latest_version: "1.2.0",
      deprecated: false,
      versions: [
        %{version: "1.1.0", integrity: "sha512-one-one"},
        %{version: "1.2.0", integrity: "sha512-one-two"}
      ]
    }
  end

  defp dump(args) do
    capture_io(fn -> Dump.run(args) end)
  end

  defp read_dump(path) do
    path |> File.read!() |> Jason.decode!()
  end

  @compared_adaptor_fields ~w(name source description homepage repository
                              license latest_version deprecated schema_data
                              schema_sha256)a

  @compared_version_fields ~w(version integrity tarball_url size_bytes
                              dependencies peer_dependencies published_at
                              deprecated)a

  # Every version row is stamped with the same `inserted_at`, so
  # `list_versions/2`'s ordering is not stable enough to compare on.
  defp comparable(name, source) do
    adaptor =
      name |> Catalogue.get_adaptor(source) |> Map.take(@compared_adaptor_fields)

    versions =
      name
      |> Catalogue.list_versions(source)
      |> Enum.map(&Map.take(&1, @compared_version_fields))
      |> Enum.sort_by(& &1.version)

    {adaptor, versions}
  end

  describe "run/1" do
    setup do
      {:ok, _} = Catalogue.upsert_adaptor(http_record(:npm))
      {:ok, _} = Catalogue.upsert_adaptor(common_record(:npm))
      :ok
    end

    test "writes every adaptor and its versions to --path", %{tmp_dir: tmp_dir} do
      path = Path.join(tmp_dir, "dump.json")
      refute File.exists?(path)

      dump(["--path", path])

      records = read_dump(path)
      assert length(records) == 2

      http = Enum.find(records, &(&1["name"] == "@openfn/language-http"))

      assert http["source"] == "npm"
      assert http["latest_version"] == "2.1.0"
      assert http["description"] == "HTTP adaptor"
      assert http["schema_data"] == ~s({"type":"object"})

      assert http["versions"] |> Enum.map(& &1["version"]) |> Enum.sort() ==
               ["2.0.0", "2.1.0"]

      two_one = Enum.find(http["versions"], &(&1["version"] == "2.1.0"))
      assert two_one["integrity"] == "sha512-two-one"
      assert two_one["size_bytes"] == 12_345
      assert two_one["dependencies"] == %{"axios" => "^1.5.0"}
    end

    test "omits row identity and timestamps the importer regenerates", %{
      tmp_dir: tmp_dir
    } do
      path = Path.join(tmp_dir, "dump.json")
      dump(["--path", path])

      [record | _] = read_dump(path)

      refute Map.has_key?(record, "id")
      refute Map.has_key?(record, "inserted_at")
      refute Map.has_key?(record, "updated_at")
      refute Map.has_key?(record, "checked_at")

      [version | _] = record["versions"]

      refute Map.has_key?(version, "id")
      refute Map.has_key?(version, "adaptor_id")
      refute Map.has_key?(version, "inserted_at")
    end

    test "round-trips back through lightning.adaptors.import", %{
      tmp_dir: tmp_dir
    } do
      path = Path.join(tmp_dir, "dump.json")
      dump(["--path", path])

      names = ~w(@openfn/language-common @openfn/language-http)
      before = Enum.map(names, &comparable(&1, :npm))

      Catalogue.delete_all_for_source(:npm)
      assert Catalogue.list_adaptors(:npm) == []

      {:ok, 2} =
        Lightning.Adaptors.seed_from_file(path, source: :npm, replace: true)

      assert Enum.map(names, &comparable(&1, :npm)) == before
    end

    test "includes adaptors the catalogue listing excludes", %{
      tmp_dir: tmp_dir
    } do
      {:ok, _} =
        Catalogue.upsert_adaptor(%{
          name: "@openfn/language-collections",
          source: :npm,
          latest_version: "1.0.0",
          versions: [%{version: "1.0.0"}]
        })

      path = Path.join(tmp_dir, "dump.json")
      dump(["--path", path])

      names = read_dump(path) |> Enum.map(& &1["name"])
      assert "@openfn/language-collections" in names
    end

    test "--source local dumps only local rows", %{tmp_dir: tmp_dir} do
      {:ok, _} =
        Catalogue.upsert_adaptor(%{
          name: "@openfn/language-local-only",
          source: :local,
          latest_version: "0.1.0",
          versions: [%{version: "0.1.0"}]
        })

      path = Path.join(tmp_dir, "dump.json")
      dump(["--path", path, "--source", "local"])

      assert [%{"name" => "@openfn/language-local-only", "source" => "local"}] =
               read_dump(path)
    end

    test "raises without --path" do
      assert_raise RuntimeError, ~r/--path/, fn -> dump([]) end
    end

    test "raises on an unknown --source", %{tmp_dir: tmp_dir} do
      path = Path.join(tmp_dir, "dump.json")

      assert_raise RuntimeError, ~r/Unknown --source/, fn ->
        dump(["--path", path, "--source", "nope"])
      end
    end
  end
end
