defmodule Lightning.Adaptors.CatalogueListingTest do
  use Lightning.DataCase, async: true

  alias Lightning.Adaptors.Catalogue

  describe "catalogue/1" do
    test "returns name, latest_version, repository, icon fields, and full version list" do
      {:ok, _adaptor} =
        Catalogue.upsert_adaptor(%{
          name: "@openfn/language-http",
          source: :npm,
          latest_version: "2.0.0",
          repository: "https://github.com/openfn/language-http",
          icon_square_ext: "png",
          icon_square_sha256: :crypto.hash(:sha256, "square"),
          icon_rectangle_ext: "svg",
          icon_rectangle_sha256: :crypto.hash(:sha256, "rectangle"),
          versions: [
            version_record("1.0.0"),
            version_record("2.0.0")
          ]
        })

      assert [entry] = Catalogue.catalogue(:npm)

      assert entry.name == "@openfn/language-http"
      assert entry.latest_version == "2.0.0"
      assert entry.repository == "https://github.com/openfn/language-http"
      assert entry.icon_square_ext == "png"
      assert entry.icon_rectangle_ext == "svg"
      assert Enum.sort(entry.versions) == ["1.0.0", "2.0.0"]
    end

    test "is source-scoped" do
      {:ok, _} =
        Catalogue.upsert_adaptor(%{
          name: "@openfn/language-http",
          source: :npm,
          latest_version: "1.0.0",
          versions: [version_record("1.0.0")]
        })

      assert Catalogue.catalogue(:local) == []
    end

    test "returns an empty list for an adaptor with no versions" do
      {:ok, _} =
        Catalogue.upsert_adaptor(%{
          name: "@openfn/language-http",
          source: :npm,
          latest_version: "1.0.0",
          versions: []
        })

      assert [%{versions: []}] = Catalogue.catalogue(:npm)
    end

    test "omits the excluded adaptors" do
      for name <- [
            "@openfn/language-devtools",
            "@openfn/language-template",
            "@openfn/language-fhir-jembi",
            "@openfn/language-collections",
            "@openfn/language-http"
          ] do
        {:ok, _} =
          Catalogue.upsert_adaptor(%{
            name: name,
            source: :npm,
            latest_version: "1.0.0",
            versions: [version_record("1.0.0")]
          })
      end

      assert [%{name: "@openfn/language-http"}] = Catalogue.catalogue(:npm)
    end
  end

  describe "catalogue_stamp/1" do
    test "returns a nil timestamp and zero count when the source has no rows" do
      assert Catalogue.catalogue_stamp(:npm) == {nil, 0}
    end

    test "reflects the adaptor row's updated_at when there are no versions" do
      {:ok, adaptor} =
        Catalogue.upsert_adaptor(%{
          name: "@openfn/language-http",
          source: :npm,
          latest_version: "1.0.0",
          versions: []
        })

      assert {stamp, 0} = Catalogue.catalogue_stamp(:npm)
      assert stamp == adaptor.updated_at
    end

    test "advances when a new version is published, without touching the adaptor row" do
      {:ok, _adaptor} =
        Catalogue.upsert_adaptor(%{
          name: "@openfn/language-http",
          source: :npm,
          latest_version: "1.0.0",
          versions: [version_record("1.0.0")]
        })

      {before_stamp, _count} = Catalogue.catalogue_stamp(:npm)

      {:ok, _adaptor} =
        Catalogue.upsert_adaptor(%{
          name: "@openfn/language-http",
          source: :npm,
          latest_version: "1.0.0",
          versions: [version_record("1.0.0"), version_record("1.1.0")]
        })

      {after_stamp, count} = Catalogue.catalogue_stamp(:npm)

      assert DateTime.after?(after_stamp, before_stamp)
      assert count == 2
    end

    test "changes when a version is removed from an adaptor that doesn't hold the current max" do
      {:ok, _b} =
        Catalogue.upsert_adaptor(%{
          name: "@openfn/language-b",
          source: :npm,
          latest_version: "1.0.0",
          versions: [version_record("1.0.0")]
        })

      {:ok, _a} =
        Catalogue.upsert_adaptor(%{
          name: "@openfn/language-a",
          source: :npm,
          latest_version: "1.0.0",
          versions: [version_record("1.0.0")]
        })

      before_stamp = Catalogue.catalogue_stamp(:npm)

      {:ok, _b} =
        Catalogue.upsert_adaptor(%{
          name: "@openfn/language-b",
          source: :npm,
          latest_version: "1.0.0",
          versions: []
        })

      assert Catalogue.catalogue_stamp(:npm) != before_stamp
    end
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
end
