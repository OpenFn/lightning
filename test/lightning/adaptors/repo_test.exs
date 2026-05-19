defmodule Lightning.Adaptors.RepoTest do
  use Lightning.DataCase, async: true

  alias Lightning.Adaptors.Repo, as: AdaptorRepo
  alias Lightning.Adaptors.Repo.Adaptor
  alias Lightning.Adaptors.Repo.AdaptorVersion

  describe "upsert_adaptor/1 — initial insert" do
    test "inserts the adaptor row and its versions in one transaction" do
      record =
        adaptor_record(
          versions: [version_record("1.0.0"), version_record("1.1.0")]
        )

      assert {:ok, %Adaptor{} = adaptor} = AdaptorRepo.upsert_adaptor(record)

      assert adaptor.name == "@openfn/language-http"
      assert adaptor.source == :npm
      assert adaptor.latest_version == "1.0.0"
      assert %DateTime{} = adaptor.checked_at
      assert %DateTime{} = adaptor.updated_at

      versions = AdaptorRepo.list_versions(adaptor.name, :npm)

      assert versions |> Enum.map(& &1.version) |> Enum.sort() == [
               "1.0.0",
               "1.1.0"
             ]

      assert Enum.all?(versions, &(&1.adaptor_id == adaptor.id))
    end

    test "accepts a record with no versions" do
      record = adaptor_record(versions: [])

      assert {:ok, %Adaptor{} = adaptor} = AdaptorRepo.upsert_adaptor(record)
      assert AdaptorRepo.list_versions(adaptor.name, :npm) == []
    end
  end

  describe "upsert_adaptor/1 — idempotency (§12.2)" do
    test "re-upserting the same record advances :checked_at but not :updated_at" do
      {:ok, first} = AdaptorRepo.upsert_adaptor(adaptor_record())

      Process.sleep(5)

      {:ok, second} = AdaptorRepo.upsert_adaptor(adaptor_record())

      assert second.id == first.id
      assert second.updated_at == first.updated_at
      assert DateTime.compare(second.checked_at, first.checked_at) == :gt
    end
  end

  describe "upsert_adaptor/1 — diff-aware :updated_at" do
    test "changing :latest_version bumps :updated_at" do
      {:ok, first} = AdaptorRepo.upsert_adaptor(adaptor_record())

      Process.sleep(5)

      {:ok, second} =
        AdaptorRepo.upsert_adaptor(adaptor_record(latest_version: "1.1.0"))

      assert second.latest_version == "1.1.0"
      assert DateTime.compare(second.updated_at, first.updated_at) == :gt
    end

    test "changing :description bumps :updated_at" do
      {:ok, first} = AdaptorRepo.upsert_adaptor(adaptor_record())

      Process.sleep(5)

      {:ok, second} =
        AdaptorRepo.upsert_adaptor(adaptor_record(description: "new copy"))

      assert second.description == "new copy"
      assert DateTime.compare(second.updated_at, first.updated_at) == :gt
    end
  end

  describe "upsert_adaptor/1 — version row replacement (§12.2)" do
    test "replaces version rows atomically" do
      {:ok, _adaptor} =
        AdaptorRepo.upsert_adaptor(
          adaptor_record(
            versions: [version_record("1.0.0"), version_record("1.1.0")]
          )
        )

      assert AdaptorRepo.list_versions("@openfn/language-http", :npm)
             |> Enum.map(& &1.version)
             |> Enum.sort() == ["1.0.0", "1.1.0"]

      {:ok, _adaptor} =
        AdaptorRepo.upsert_adaptor(
          adaptor_record(
            versions: [
              version_record("1.1.0"),
              version_record("1.2.0"),
              version_record("2.0.0")
            ]
          )
        )

      assert AdaptorRepo.list_versions("@openfn/language-http", :npm)
             |> Enum.map(& &1.version)
             |> Enum.sort() == ["1.1.0", "1.2.0", "2.0.0"]
    end

    test "shrinking the version set drops the missing rows" do
      {:ok, _} =
        AdaptorRepo.upsert_adaptor(
          adaptor_record(
            versions: [version_record("1.0.0"), version_record("1.1.0")]
          )
        )

      {:ok, _} =
        AdaptorRepo.upsert_adaptor(
          adaptor_record(versions: [version_record("1.1.0")])
        )

      assert [%AdaptorVersion{version: "1.1.0"}] =
               AdaptorRepo.list_versions("@openfn/language-http", :npm)
    end

    test "persists version-row payload fields verbatim" do
      payload = %{
        version: "1.0.0",
        integrity: "sha512-deadbeef==",
        tarball_url: "https://registry.npmjs.org/x/-/x-1.0.0.tgz",
        size_bytes: 4321,
        dependencies: %{"axios" => "^1.0.0"},
        peer_dependencies: %{"react" => "^18"},
        published_at: ~U[2026-05-01 10:00:00.000000Z],
        deprecated: false
      }

      {:ok, _} = AdaptorRepo.upsert_adaptor(adaptor_record(versions: [payload]))

      assert [version] =
               AdaptorRepo.list_versions("@openfn/language-http", :npm)

      assert version.integrity == payload.integrity
      assert version.tarball_url == payload.tarball_url
      assert version.size_bytes == payload.size_bytes
      assert version.dependencies == payload.dependencies
      assert version.peer_dependencies == payload.peer_dependencies
      assert version.published_at == payload.published_at
      assert version.deprecated == payload.deprecated
    end
  end

  describe "upsert_adaptor/1 — source isolation" do
    test "the same name can coexist across sources" do
      {:ok, npm_row} =
        AdaptorRepo.upsert_adaptor(adaptor_record(source: :npm))

      {:ok, local_row} =
        AdaptorRepo.upsert_adaptor(adaptor_record(source: :local))

      assert npm_row.id != local_row.id
      assert npm_row.source == :npm
      assert local_row.source == :local
    end
  end

  describe "touch_checked_at/2 (§12.2)" do
    test "advances :checked_at and leaves :updated_at alone" do
      {:ok, original} = AdaptorRepo.upsert_adaptor(adaptor_record())

      Process.sleep(5)

      assert :ok = AdaptorRepo.touch_checked_at(original.name, :npm)

      reloaded = AdaptorRepo.get_adaptor(original.name, :npm)
      assert DateTime.compare(reloaded.checked_at, original.checked_at) == :gt
      assert reloaded.updated_at == original.updated_at
    end

    test "is a no-op for an unknown (name, source) — does not require loading the row" do
      assert :ok = AdaptorRepo.touch_checked_at("@openfn/never-existed", :npm)
      assert AdaptorRepo.get_adaptor("@openfn/never-existed", :npm) == nil
    end

    test "is source-scoped" do
      {:ok, npm_row} =
        AdaptorRepo.upsert_adaptor(adaptor_record(source: :npm))

      {:ok, local_row} =
        AdaptorRepo.upsert_adaptor(adaptor_record(source: :local))

      Process.sleep(5)

      :ok = AdaptorRepo.touch_checked_at(npm_row.name, :npm)

      reloaded_npm = AdaptorRepo.get_adaptor(npm_row.name, :npm)
      reloaded_local = AdaptorRepo.get_adaptor(local_row.name, :local)

      assert DateTime.compare(reloaded_npm.checked_at, npm_row.checked_at) == :gt
      assert reloaded_local.checked_at == local_row.checked_at
    end
  end

  describe "stalest/2 (§12.2)" do
    test "orders by :checked_at ascending" do
      base = DateTime.utc_now()

      seed_adaptor(name: "@openfn/a", checked_at: DateTime.add(base, -300))
      seed_adaptor(name: "@openfn/b", checked_at: DateTime.add(base, -100))
      seed_adaptor(name: "@openfn/c", checked_at: DateTime.add(base, -200))

      assert AdaptorRepo.stalest(10, :npm) |> Enum.map(& &1.name) ==
               ["@openfn/a", "@openfn/c", "@openfn/b"]
    end

    test "honours the limit" do
      base = DateTime.utc_now()
      seed_adaptor(name: "@openfn/a", checked_at: DateTime.add(base, -300))
      seed_adaptor(name: "@openfn/b", checked_at: DateTime.add(base, -200))
      seed_adaptor(name: "@openfn/c", checked_at: DateTime.add(base, -100))

      assert length(AdaptorRepo.stalest(2, :npm)) == 2
    end

    test "filters by source" do
      seed_adaptor(name: "@openfn/a", source: :npm)
      seed_adaptor(name: "@openfn/a", source: :local)

      assert [%Adaptor{source: :npm}] = AdaptorRepo.stalest(10, :npm)
      assert [%Adaptor{source: :local}] = AdaptorRepo.stalest(10, :local)
    end
  end

  describe "max_checked_at/1" do
    test "returns the largest :checked_at for the given source" do
      base = DateTime.utc_now()
      newest = DateTime.add(base, -100)
      seed_adaptor(name: "@openfn/a", checked_at: DateTime.add(base, -300))
      seed_adaptor(name: "@openfn/b", checked_at: newest)

      assert AdaptorRepo.max_checked_at(:npm) == newest
    end

    test "returns nil when the source has no rows" do
      seed_adaptor(name: "@openfn/a", source: :npm)
      assert AdaptorRepo.max_checked_at(:local) == nil
    end
  end

  describe "get_adaptor/2" do
    test "returns the matching adaptor" do
      {:ok, inserted} = AdaptorRepo.upsert_adaptor(adaptor_record())
      reloaded = AdaptorRepo.get_adaptor(inserted.name, :npm)

      assert %Adaptor{} = reloaded
      assert reloaded.id == inserted.id
    end

    test "returns nil when not found" do
      assert AdaptorRepo.get_adaptor("@openfn/never-existed", :npm) == nil
    end

    test "is source-scoped" do
      {:ok, _} = AdaptorRepo.upsert_adaptor(adaptor_record(source: :npm))
      assert AdaptorRepo.get_adaptor("@openfn/language-http", :local) == nil
    end
  end

  describe "list_package_metas/1" do
    test "returns the lean projection without heavy JSONB columns" do
      {:ok, _} =
        AdaptorRepo.upsert_adaptor(
          adaptor_record(
            description: "yep",
            schema_data: %{"big" => "json", "nested" => %{"more" => "stuff"}}
          )
        )

      assert [meta] = AdaptorRepo.list_package_metas(:npm)

      assert meta.name == "@openfn/language-http"
      assert meta.latest_version == "1.0.0"
      assert meta.description == "yep"
      assert meta.deprecated == false
      assert %DateTime{} = meta.updated_at

      refute Map.has_key?(meta, :schema_data)
      refute Map.has_key?(meta, :homepage)
    end

    test "filters by source" do
      {:ok, _} = AdaptorRepo.upsert_adaptor(adaptor_record(source: :npm))
      {:ok, _} = AdaptorRepo.upsert_adaptor(adaptor_record(source: :local))

      assert [%{name: "@openfn/language-http"}] =
               AdaptorRepo.list_package_metas(:npm)

      assert [%{name: "@openfn/language-http"}] =
               AdaptorRepo.list_package_metas(:local)
    end
  end

  describe "list_adaptors/1" do
    test "returns full structs filtered by source" do
      {:ok, _} = AdaptorRepo.upsert_adaptor(adaptor_record(source: :npm))
      {:ok, _} = AdaptorRepo.upsert_adaptor(adaptor_record(source: :local))

      assert [%Adaptor{source: :npm}] = AdaptorRepo.list_adaptors(:npm)
      assert [%Adaptor{source: :local}] = AdaptorRepo.list_adaptors(:local)
    end
  end

  describe "list_missing_icons/1" do
    test "returns rows where either icon shape sha256 is nil" do
      {:ok, _} = AdaptorRepo.upsert_adaptor(adaptor_record(name: "@openfn/a"))

      {:ok, _} =
        AdaptorRepo.upsert_adaptor(
          adaptor_record(
            name: "@openfn/b",
            icon_square_ext: "png",
            icon_square_sha256: :crypto.hash(:sha256, "x")
          )
        )

      {:ok, _} =
        AdaptorRepo.upsert_adaptor(
          adaptor_record(
            name: "@openfn/c",
            icon_square_ext: "png",
            icon_square_sha256: :crypto.hash(:sha256, "y"),
            icon_rectangle_ext: "png",
            icon_rectangle_sha256: :crypto.hash(:sha256, "z")
          )
        )

      names =
        AdaptorRepo.list_missing_icons(:npm)
        |> Enum.map(& &1.name)
        |> Enum.sort()

      assert names == ["@openfn/a", "@openfn/b"]
    end

    test "is source-scoped" do
      {:ok, _} =
        AdaptorRepo.upsert_adaptor(
          adaptor_record(name: "@openfn/x", source: :local)
        )

      assert AdaptorRepo.list_missing_icons(:npm) == []
      assert [%{name: "@openfn/x"}] = AdaptorRepo.list_missing_icons(:local)
    end
  end

  describe "update_icons/3" do
    test "writes only icon columns and bumps :updated_at" do
      {:ok, before} = AdaptorRepo.upsert_adaptor(adaptor_record())
      Process.sleep(5)
      sha = :crypto.hash(:sha256, "PNG")

      assert {1, nil} =
               AdaptorRepo.update_icons(before.name, :npm, %{
                 icon_square_ext: "png",
                 icon_square_sha256: sha
               })

      after_row = AdaptorRepo.get_adaptor(before.name, :npm)

      assert after_row.icon_square_ext == "png"
      assert after_row.icon_square_sha256 == sha
      assert after_row.latest_version == before.latest_version
      assert DateTime.compare(after_row.updated_at, before.updated_at) == :gt
    end

    test "ignores keys outside the icon set" do
      {:ok, before} = AdaptorRepo.upsert_adaptor(adaptor_record())

      AdaptorRepo.update_icons(before.name, :npm, %{
        latest_version: "9.9.9",
        icon_square_ext: "svg",
        icon_square_sha256: :crypto.hash(:sha256, "S")
      })

      after_row = AdaptorRepo.get_adaptor(before.name, :npm)
      assert after_row.latest_version == before.latest_version
      assert after_row.icon_square_ext == "svg"
    end

    test "leaves version rows untouched" do
      {:ok, before} =
        AdaptorRepo.upsert_adaptor(
          adaptor_record(
            versions: [version_record("1.0.0"), version_record("2.0.0")]
          )
        )

      AdaptorRepo.update_icons(before.name, :npm, %{
        icon_square_ext: "png",
        icon_square_sha256: :crypto.hash(:sha256, "P")
      })

      versions = AdaptorRepo.list_versions(before.name, :npm)
      assert length(versions) == 2
    end
  end

  defp adaptor_record(overrides \\ []) do
    overrides = Map.new(overrides)

    %{
      name: "@openfn/language-http",
      source: :npm,
      latest_version: "1.0.0",
      description: "HTTP adaptor",
      homepage: nil,
      repository: nil,
      license: "LGPL-3.0",
      deprecated: false,
      schema_data: nil,
      schema_sha256: nil,
      icon_square_ext: nil,
      icon_rectangle_ext: nil,
      icon_square_sha256: nil,
      icon_rectangle_sha256: nil,
      versions: [version_record("1.0.0")]
    }
    |> Map.merge(overrides)
  end

  defp version_record(version) do
    %{
      version: version,
      integrity: "sha512-#{version}",
      tarball_url: "https://example.com/x/-/x-#{version}.tgz",
      size_bytes: 1024,
      dependencies: %{},
      peer_dependencies: %{},
      published_at: nil,
      deprecated: false
    }
  end

  defp seed_adaptor(opts) do
    attrs =
      %{
        name: "@openfn/language-http",
        source: :npm,
        latest_version: "1.0.0",
        checked_at: DateTime.utc_now()
      }
      |> Map.merge(Map.new(opts))

    {:ok, adaptor} =
      %Adaptor{}
      |> Adaptor.changeset(attrs)
      |> Lightning.Repo.insert()

    adaptor
  end
end
