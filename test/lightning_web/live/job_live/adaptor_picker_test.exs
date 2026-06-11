defmodule LightningWeb.JobLive.AdaptorPickerTest do
  # async: false because we touch the production-named
  # `Lightning.Adaptors` supervisor's shared Cachex.
  use LightningWeb.ConnCase, async: false

  import Lightning.AdaptorTestHelpers

  alias LightningWeb.JobLive.AdaptorPicker

  describe "get_adaptor_version_options/1" do
    setup do
      {:ok, _} =
        Lightning.Adaptors.Repo.upsert_adaptor(%{
          name: "@openfn/language-common",
          source: :npm,
          latest_version: "1.6.2",
          description: nil,
          homepage: nil,
          repository: nil,
          license: nil,
          deprecated: false,
          schema_data: nil,
          schema_sha256: nil,
          versions:
            Enum.map(["1.0.0", "1.6.2", "2.0.0"], fn v ->
              %{
                version: v,
                integrity: "sha512-#{v}",
                tarball_url: "https://example.com/x-#{v}.tgz",
                size_bytes: 1024,
                dependencies: %{},
                peer_dependencies: %{},
                published_at: nil,
                deprecated: false
              }
            end)
        })

      clear_global_adaptors_cache()

      :ok
    end

    test "returns sorted versions with latest option when adaptor exists" do
      adaptor_name = "@openfn/language-common"

      {module_name, version, adaptor_names, versions} =
        AdaptorPicker.get_adaptor_version_options(adaptor_name)

      assert module_name == adaptor_name
      assert version == nil
      assert {"common", adaptor_name} in adaptor_names

      # Check that versions are properly formatted and ordered
      latest_version = List.first(versions)

      assert match?(
               [key: "latest " <> _, value: "@openfn/language-common@latest"],
               latest_version
             )

      # Get all non-latest versions
      [_latest | specific_versions] = versions

      # Verify versions are in descending order
      version_numbers =
        Enum.map(specific_versions, fn [key: version, value: _] ->
          Version.parse!(version)
        end)

      assert version_numbers == Enum.sort(version_numbers, {:desc, Version})
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
