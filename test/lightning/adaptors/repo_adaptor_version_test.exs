defmodule Lightning.Adaptors.Repo.AdaptorVersionTest do
  use ExUnit.Case, async: true

  alias Lightning.Adaptors.Repo.AdaptorVersion

  @adaptor_id Ecto.UUID.generate()

  @valid_attrs %{
    adaptor_id: @adaptor_id,
    version: "1.2.3"
  }

  describe "changeset/2 — required fields" do
    test "is valid with the minimum required set" do
      changeset = AdaptorVersion.changeset(%AdaptorVersion{}, @valid_attrs)
      assert changeset.valid?
    end

    test "requires :adaptor_id" do
      changeset =
        AdaptorVersion.changeset(
          %AdaptorVersion{},
          Map.delete(@valid_attrs, :adaptor_id)
        )

      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset, :adaptor_id)
    end

    test "requires :version" do
      changeset =
        AdaptorVersion.changeset(
          %AdaptorVersion{},
          Map.delete(@valid_attrs, :version)
        )

      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset, :version)
    end
  end

  describe "changeset/2 — optional fields round-trip" do
    test "casts :integrity" do
      attrs = Map.put(@valid_attrs, :integrity, "sha512-abcdef==")
      changeset = AdaptorVersion.changeset(%AdaptorVersion{}, attrs)

      assert changeset.valid?

      assert Ecto.Changeset.get_change(changeset, :integrity) ==
               "sha512-abcdef=="
    end

    test "casts :tarball_url" do
      attrs =
        Map.put(
          @valid_attrs,
          :tarball_url,
          "https://registry.npmjs.org/x/-/x-1.2.3.tgz"
        )

      changeset = AdaptorVersion.changeset(%AdaptorVersion{}, attrs)

      assert changeset.valid?

      assert Ecto.Changeset.get_change(changeset, :tarball_url) ==
               "https://registry.npmjs.org/x/-/x-1.2.3.tgz"
    end

    test "casts :size_bytes" do
      attrs = Map.put(@valid_attrs, :size_bytes, 12_345)
      changeset = AdaptorVersion.changeset(%AdaptorVersion{}, attrs)

      assert changeset.valid?
      assert Ecto.Changeset.get_change(changeset, :size_bytes) == 12_345
    end

    test "casts :dependencies as a map (no structural validation)" do
      deps = %{"axios" => "^1.0.0", "lodash" => "4.17.21"}
      attrs = Map.put(@valid_attrs, :dependencies, deps)
      changeset = AdaptorVersion.changeset(%AdaptorVersion{}, attrs)

      assert changeset.valid?
      assert Ecto.Changeset.get_change(changeset, :dependencies) == deps
    end

    test "casts :peer_dependencies as a map (no structural validation)" do
      peers = %{"react" => "^18.0.0"}
      attrs = Map.put(@valid_attrs, :peer_dependencies, peers)
      changeset = AdaptorVersion.changeset(%AdaptorVersion{}, attrs)

      assert changeset.valid?

      assert Ecto.Changeset.get_change(changeset, :peer_dependencies) ==
               peers
    end

    test "accepts an arbitrarily-shaped :dependencies map" do
      weird = %{"a" => 1, "b" => %{"nested" => true}, "c" => nil}
      attrs = Map.put(@valid_attrs, :dependencies, weird)

      assert AdaptorVersion.changeset(%AdaptorVersion{}, attrs).valid?
    end

    test "casts :published_at" do
      ts = ~U[2026-05-14 12:00:00.000000Z]
      attrs = Map.put(@valid_attrs, :published_at, ts)
      changeset = AdaptorVersion.changeset(%AdaptorVersion{}, attrs)

      assert changeset.valid?
      assert Ecto.Changeset.get_change(changeset, :published_at) == ts
    end

    test "casts :deprecated" do
      attrs = Map.put(@valid_attrs, :deprecated, true)
      changeset = AdaptorVersion.changeset(%AdaptorVersion{}, attrs)

      assert changeset.valid?
      assert Ecto.Changeset.get_change(changeset, :deprecated) == true
    end

    test "defaults :deprecated to false on a fresh struct" do
      assert %AdaptorVersion{}.deprecated == false
    end
  end

  describe "changeset/2 — unique_constraint" do
    test "registers a unique_constraint on [:adaptor_id, :version]" do
      changeset = AdaptorVersion.changeset(%AdaptorVersion{}, @valid_attrs)

      assert Enum.any?(changeset.constraints, fn c ->
               c.type == :unique and
                 c.constraint == "adaptor_versions_adaptor_id_version_index"
             end)
    end
  end

  describe "changeset/2 — FK constraint" do
    test "registers a foreign_key constraint on the :adaptor association" do
      changeset = AdaptorVersion.changeset(%AdaptorVersion{}, @valid_attrs)

      assert Enum.any?(changeset.constraints, fn c ->
               c.type == :foreign_key and c.field == :adaptor
             end)
    end
  end

  describe "schema" do
    test "belongs_to :adaptor uses binary_id" do
      assoc = AdaptorVersion.__schema__(:association, :adaptor)
      assert assoc.related == Lightning.Adaptors.Repo.Adaptor
      assert assoc.owner_key == :adaptor_id
    end

    test ":adaptor_id field is binary_id" do
      assert AdaptorVersion.__schema__(:type, :adaptor_id) == :binary_id
    end

    test ":id field is binary_id" do
      assert AdaptorVersion.__schema__(:type, :id) == :binary_id
    end

    test "has :inserted_at but not :updated_at" do
      fields = AdaptorVersion.__schema__(:fields)
      assert :inserted_at in fields
      refute :updated_at in fields
    end
  end

  defp errors_on(changeset, field) do
    for {f, {msg, _opts}} <- changeset.errors, f == field, do: msg
  end
end
