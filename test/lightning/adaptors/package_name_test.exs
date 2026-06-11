defmodule Lightning.Adaptors.PackageNameTest do
  use Lightning.DataCase, async: false

  import Lightning.Factories

  alias Lightning.Adaptors.PackageName

  describe "parse/1" do
    test "splits scoped name and semver version" do
      assert PackageName.parse("@openfn/language-common@1.2.3") ==
               {"@openfn/language-common", "1.2.3"}
    end

    test "splits unscoped name and version" do
      assert PackageName.parse("foo@2.0.0") == {"foo", "2.0.0"}
    end

    test "returns the name with nil version when no @version is given" do
      assert PackageName.parse("@openfn/language-common") ==
               {"@openfn/language-common", nil}
    end

    test "treats the @local literal as a version" do
      assert PackageName.parse("@openfn/language-common@local") ==
               {"@openfn/language-common", "local"}
    end

    test "treats the @latest literal as a version" do
      assert PackageName.parse("@openfn/language-common@latest") ==
               {"@openfn/language-common", "latest"}
    end

    test "returns {nil, nil} for nil input" do
      assert PackageName.parse(nil) == {nil, nil}
    end

    test "returns {nil, nil} for malformed input" do
      assert PackageName.parse("") == {nil, nil}
    end
  end

  describe "to_wire/1" do
    test "passes through concrete semver unchanged" do
      assert PackageName.to_wire("@openfn/language-common@1.6.2") ==
               "@openfn/language-common@1.6.2"
    end

    test "returns empty string for nil input" do
      assert PackageName.to_wire(nil) == ""
    end

    test "preserves @local literal regardless of source" do
      assert PackageName.to_wire("@openfn/language-common@local") ==
               "@openfn/language-common@local"
    end

    test "resolves @latest to the concrete latest_version from Adaptors.Repo" do
      insert(:adaptor,
        name: "@openfn/language-common",
        source: :npm,
        latest_version: "9.9.9"
      )

      assert PackageName.to_wire("@openfn/language-common@latest") ==
               "@openfn/language-common@9.9.9"
    end

    test "falls back to @latest literal when adaptor is unknown" do
      assert PackageName.to_wire("@openfn/never-existed@latest") ==
               "@openfn/never-existed@latest"
    end
  end
end
