defmodule Lightning.Adaptors.APITest do
  use ExUnit.Case, async: false

  setup do
    # Ensure the new Adaptors Registry is available for tests
    unless Process.whereis(Lightning.Adaptors.Registry) do
      start_supervised!(
        {Registry, keys: :unique, name: Lightning.Adaptors.Registry}
      )
    end

    :ok
  end

  describe "Lightning.Adaptors.API.all/1" do
    test "returns list of adaptor names using named instance" do
      adaptors_name = :"api_test_#{:rand.uniform(10000)}"

      start_supervised!(
        {Lightning.Adaptors.Supervisor,
         [
           name: adaptors_name,
           strategy: {MockAdaptorStrategy, [config: "foo"]}
         ]}
      )

      assert {:ok, result} = Lightning.Adaptors.API.all(adaptors_name)

      assert result == [
               "@openfn/language-foo",
               "@openfn/language-bar"
             ]
    end

    test "returns list of adaptor names using default instance" do
      temp_name = Lightning.Adaptors

      start_supervised!(
        {Lightning.Adaptors.Supervisor,
         [
           name: temp_name,
           strategy: {MockAdaptorStrategy, [config: "foo"]}
         ]}
      )

      # Wait for supervisor to fully start
      Process.sleep(100)

      assert {:ok, result} = Lightning.Adaptors.API.all()

      assert result == [
               "@openfn/language-foo",
               "@openfn/language-bar"
             ]
    end
  end

  describe "Lightning.Adaptors.API.versions_for/2" do
    test "returns versions for a cached adaptor" do
      adaptors_name = :"api_versions_test_#{:rand.uniform(10000)}"

      start_supervised!(
        {Lightning.Adaptors.Supervisor,
         [
           name: adaptors_name,
           strategy: {MockAdaptorStrategy, [config: "foo"]}
         ]}
      )

      # Populate cache first
      Lightning.Adaptors.API.all(adaptors_name)

      # Test versions_for
      {:ok, versions} =
        Lightning.Adaptors.API.versions_for(
          adaptors_name,
          "@openfn/language-foo"
        )

      expected_versions = %{
        "1.0.0" => %{"version" => "1.0.0"},
        "2.0.0" => %{"version" => "2.0.0"},
        "2.1.0" => %{"version" => "2.1.0"}
      }

      assert versions == expected_versions
    end

    test "returns error for non-existent adaptor" do
      adaptors_name = :"api_versions_not_found_test_#{:rand.uniform(10000)}"

      start_supervised!(
        {Lightning.Adaptors.Supervisor,
         [
           name: adaptors_name,
           strategy: {MockAdaptorStrategy, [config: "foo"]}
         ]}
      )

      # Populate cache first
      Lightning.Adaptors.API.all(adaptors_name)

      # Test versions_for with non-existent adaptor
      result =
        Lightning.Adaptors.API.versions_for(
          adaptors_name,
          "@openfn/language-nonexistent"
        )

      assert {:error, :not_found} = result
    end
  end

  describe "Lightning.Adaptors.API.latest_for/2" do
    test "returns latest version for a cached adaptor" do
      adaptors_name = :"api_latest_test_#{:rand.uniform(10000)}"

      start_supervised!(
        {Lightning.Adaptors.Supervisor,
         [
           name: adaptors_name,
           strategy: {MockAdaptorStrategy, [config: "foo"]}
         ]}
      )

      # Test latest_for
      {:ok, nil} =
        Lightning.Adaptors.API.latest_for(adaptors_name, "@openfn/language-foo")

      assert {:ok, %{"version" => "2.1.0"}} =
               Lightning.Adaptors.API.latest_for(
                 adaptors_name,
                 "@openfn/language-bar"
               )
    end

    test "returns error for non-existent adaptor" do
      adaptors_name = :"api_latest_not_found_test_#{:rand.uniform(10000)}"

      start_supervised!(
        {Lightning.Adaptors.Supervisor,
         [
           name: adaptors_name,
           strategy: {MockAdaptorStrategy, [config: "foo"]}
         ]}
      )

      # Populate cache first
      Lightning.Adaptors.API.all(adaptors_name)

      # Test latest_for with non-existent adaptor
      result =
        Lightning.Adaptors.API.latest_for(
          adaptors_name,
          "@openfn/language-nonexistent"
        )

      assert {:error, :not_found} = result
    end
  end

  describe "Lightning.Adaptors.API.save_cache/1" do
    test "saves cache to disk when persist_path is configured" do
      # Create a temporary file for testing
      cache_path =
        Path.join(System.tmp_dir!(), "api_test_cache_#{:rand.uniform(1000)}.bin")

      adaptors_name = :"api_persistence_save_test_#{:rand.uniform(10000)}"

      start_supervised!(
        {Lightning.Adaptors.Supervisor,
         [
           name: adaptors_name,
           strategy: {MockAdaptorStrategy, [config: "foo"]},
           persist_path: cache_path
         ]}
      )

      # Populate the cache
      Lightning.Adaptors.API.all(adaptors_name)

      # Save the cache
      assert Lightning.Adaptors.API.save_cache(adaptors_name) == :ok

      # Verify file was created
      assert File.exists?(cache_path)

      # Cleanup
      File.rm!(cache_path)
    end
  end

  describe "Lightning.Adaptors.API.restore_cache/1" do
    test "restores cache from disk when persist_path is configured" do
      cache_path =
        Path.join(System.tmp_dir!(), "api_test_cache_#{:rand.uniform(1000)}.bin")

      adaptors_name = :"api_persistence_restore_test_#{:rand.uniform(10000)}"

      start_supervised!(
        {Lightning.Adaptors.Supervisor,
         [
           name: adaptors_name,
           strategy: {MockAdaptorStrategy, [config: "foo"]},
           persist_path: cache_path
         ]}
      )

      # First, populate and save cache
      Lightning.Adaptors.API.all(adaptors_name)
      config = Lightning.Adaptors.Registry.config(adaptors_name)
      Lightning.Adaptors.API.save_cache(adaptors_name)

      # Clear the cache
      Cachex.clear(config[:cache])

      # Verify cache is empty
      {:ok, nil} = Cachex.get(config[:cache], "adaptors")

      # Restore from disk
      assert Lightning.Adaptors.API.restore_cache(adaptors_name) == :ok

      # Verify cache was restored
      {:ok, cached_adaptors} = Cachex.get(config[:cache], "adaptors")
      assert cached_adaptors == ["@openfn/language-foo", "@openfn/language-bar"]

      # Cleanup
      File.rm!(cache_path)
    end
  end

  describe "Lightning.Adaptors.API.clear_persisted_cache/1" do
    test "removes cache file when persist_path is configured" do
      cache_path =
        Path.join(System.tmp_dir!(), "api_test_cache_#{:rand.uniform(1000)}.bin")

      adaptors_name = :"api_persistence_clear_test_#{:rand.uniform(10000)}"

      start_supervised!(
        {Lightning.Adaptors.Supervisor,
         [
           name: adaptors_name,
           strategy: {MockAdaptorStrategy, [config: "foo"]},
           persist_path: cache_path
         ]}
      )

      # Create and save cache
      Lightning.Adaptors.API.all(adaptors_name)
      Lightning.Adaptors.API.save_cache(adaptors_name)

      # Verify file exists
      assert File.exists?(cache_path)

      # Clear persisted cache
      assert Lightning.Adaptors.API.clear_persisted_cache(adaptors_name) == :ok

      # Verify file was deleted
      refute File.exists?(cache_path)
    end
  end

  describe "Lightning.Adaptors.API.fetch_configuration_schema/2" do
    test "delegates to repository for configuration schema" do
      adaptors_name = :"api_config_schema_test_#{:rand.uniform(10000)}"

      start_supervised!(
        {Lightning.Adaptors.Supervisor,
         [
           name: adaptors_name,
           strategy: {MockAdaptorStrategy, [config: "foo"]}
         ]}
      )

      result =
        Lightning.Adaptors.API.fetch_configuration_schema(
          adaptors_name,
          "@openfn/language-foo"
        )

      # MockAdaptorStrategy returns {:error, :not_implemented}, which might be wrapped by Repository
      assert result in [
               {:error, :not_implemented},
               {:ok, {:ignore, :not_implemented}}
             ]
    end
  end
end
