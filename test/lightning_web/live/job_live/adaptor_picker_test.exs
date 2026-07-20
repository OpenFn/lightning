defmodule LightningWeb.JobLive.AdaptorPickerTest do
  use LightningWeb.ConnCase, async: true

  alias LightningWeb.JobLive.AdaptorPicker

  describe "get_adaptor_version_options/1" do
    test "returns latest, range and concrete version options interleaved in descending order" do
      adaptor_name = "@openfn/language-common"

      {module_name, version, adaptor_names, versions} =
        AdaptorPicker.get_adaptor_version_options(adaptor_name)

      assert module_name == adaptor_name
      assert version == nil
      assert {"common", adaptor_name} in adaptor_names

      # From the registry fixture, language-common has latest 1.6.2 and
      # versions 1.1.0, 1.1.12, 1.2.3, 1.2.14, 1.2.22, 1.6.2, 1.10.3, 2.14.0.
      # Each range option sits directly above the versions it covers.
      assert versions == [
               [key: "latest (≥ 1.6.2)", value: "#{adaptor_name}@latest"],
               [key: "2.x (latest v2)", value: "#{adaptor_name}@2.x"],
               [key: "2.14.x (latest v2.14)", value: "#{adaptor_name}@2.14.x"],
               [key: "2.14.0", value: "#{adaptor_name}@2.14.0"],
               [key: "1.x (latest v1)", value: "#{adaptor_name}@1.x"],
               [key: "1.10.x (latest v1.10)", value: "#{adaptor_name}@1.10.x"],
               [key: "1.10.3", value: "#{adaptor_name}@1.10.3"],
               [key: "1.6.x (latest v1.6)", value: "#{adaptor_name}@1.6.x"],
               [key: "1.6.2", value: "#{adaptor_name}@1.6.2"],
               [key: "1.2.x (latest v1.2)", value: "#{adaptor_name}@1.2.x"],
               [key: "1.2.22", value: "#{adaptor_name}@1.2.22"],
               [key: "1.2.14", value: "#{adaptor_name}@1.2.14"],
               [key: "1.2.3", value: "#{adaptor_name}@1.2.3"],
               [key: "1.1.x (latest v1.1)", value: "#{adaptor_name}@1.1.x"],
               [key: "1.1.12", value: "#{adaptor_name}@1.1.12"],
               [key: "1.1.0", value: "#{adaptor_name}@1.1.0"]
             ]
    end

    test "sorts pre-releases below their release and keeps them under range options" do
      # From the registry fixture, language-dhis2 has 3.0.0 plus pre-releases
      # of 3.0.0 (3.0.0-0 .. 3.0.0-4) among its versions.
      {_module_name, _version, _adaptor_names, versions} =
        AdaptorPicker.get_adaptor_version_options("@openfn/language-dhis2")

      keys = Enum.map(versions, fn [key: key, value: _value] -> key end)

      assert [
               "latest (≥ 3.0.5)",
               "3.x (latest v3)",
               "3.0.x (latest v3.0)",
               "3.0.5",
               "3.0.4",
               "3.0.2",
               "3.0.1",
               "3.0.0",
               "3.0.0-4",
               "3.0.0-3",
               "3.0.0-2",
               "3.0.0-0",
               "2.x (latest v2)",
               "2.0.x (latest v2.0)",
               "2.0.11" | _rest
             ] = keys
    end

    test "sort_versions_desc/1 orders pre-releases per semver" do
      # Per semver, a pre-release sorts BEFORE its corresponding release (so
      # descending puts the release first). Structural compare on parsed
      # `Version` structs walks struct keys alphabetically (build, major,
      # minor, patch, pre) and would put `1.0.0-beta` ahead of `1.0.0`.
      versions = ["1.0.0", "1.0.0-beta", "1.0.0-alpha", "0.9.0"]

      assert AdaptorPicker.sort_versions_desc(versions) ==
               ["1.0.0", "1.0.0-beta", "1.0.0-alpha", "0.9.0"]
    end

    test "handles adaptor with specific version" do
      adaptor_name = "@openfn/language-common@1.6.2"

      {module_name, version, adaptor_names, versions} =
        AdaptorPicker.get_adaptor_version_options(adaptor_name)

      assert module_name == "@openfn/language-common"
      assert version == "1.6.2"
      assert {"common", "@openfn/language-common"} in adaptor_names

      # Verify the specific version is in the list
      assert Enum.any?(versions, fn
               [key: "1.6.2", value: "@openfn/language-common@1.6.2"] -> true
               _ -> false
             end)
    end
  end
end
