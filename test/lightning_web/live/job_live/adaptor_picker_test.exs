defmodule LightningWeb.JobLive.AdaptorPickerTest do
  use LightningWeb.ConnCase, async: true

  alias LightningWeb.JobLive.AdaptorPicker

  describe "get_adaptor_version_options/1" do
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

      assert version_numbers == Enum.sort(version_numbers, :desc)
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
