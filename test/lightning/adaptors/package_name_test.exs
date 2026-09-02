defmodule Lightning.Adaptors.PackageNameTest do
  use ExUnit.Case, async: true

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

  describe "to_wire/2" do
    test "passes through concrete semver unchanged" do
      assert PackageName.to_wire("@openfn/language-common@1.6.2") ==
               "@openfn/language-common@1.6.2"
    end

    test "returns empty string for nil input" do
      assert PackageName.to_wire(nil) == ""
    end

    test "preserves @local literal regardless of source" do
      assert PackageName.to_wire("@openfn/language-common@local",
               source: :npm
             ) == "@openfn/language-common@local"
    end

    test "substitutes the caller-resolved version for @latest" do
      assert PackageName.to_wire("@openfn/language-common@latest",
               source: :npm,
               latest: "9.9.9"
             ) == "@openfn/language-common@9.9.9"
    end

    test "requires a resolved version for @latest under a non-local source" do
      assert_raise KeyError, fn ->
        PackageName.to_wire("@openfn/never-existed@latest", source: :npm)
      end
    end

    test "forces @local under a :local source, whatever the spec says" do
      assert PackageName.to_wire("@openfn/language-common@1.6.2",
               source: :local
             ) == "@openfn/language-common@local"

      assert PackageName.to_wire("@openfn/language-common@latest",
               source: :local
             ) == "@openfn/language-common@local"

      assert PackageName.to_wire("@openfn/language-common",
               source: :local
             ) == "@openfn/language-common@local"
    end
  end
end
