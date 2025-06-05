defmodule MockAdaptorStrategy do
  @behaviour Lightning.Adaptors.Strategy

  @impl true
  def fetch_packages(_config) do
    {:ok, ["@openfn/language-foo", "@openfn/language-bar"]}
  end

  @impl true
  def fetch_versions(_config, package_name) do
    case package_name do
      "@openfn/language-foo" ->
        {:ok,
         %{
           "1.0.0" => %{"version" => "1.0.0"},
           "2.0.0" => %{"version" => "2.0.0"},
           "2.1.0" => %{"version" => "2.1.0"}
         }}

      "@openfn/language-bar" ->
        {:ok,
         %{
           "2.0.0" => %{"version" => "2.0.0"},
           "2.1.0" => %{"version" => "2.1.0"},
           "latest" => %{"version" => "2.1.0"}
         }}

      _ ->
        {:error, :not_found}
    end
  end

  @impl true
  def validate_config(_config), do: {:ok, []}

  @impl true
  def fetch_credential_schema(_adaptor_name) do
    {:error, :not_implemented}
  end

  @impl true
  def fetch_icon(_adaptor_name, _version) do
    {:error, :not_implemented}
  end
end

defmodule Lightning.AdaptorsTest do
  use ExUnit.Case, async: true

  setup do
    # Start the Registry before each test
    start_supervised!(Lightning.Adaptors.Registry)
    :ok
  end

  describe "all/1 with registry-based API" do
    test "returns list of adaptor names using default instance" do
      adaptors_name = :"adaptors_test_#{:rand.uniform(10000)}"

      start_supervised!(
        {Lightning.Adaptors,
         [
           name: adaptors_name,
           strategy: {MockAdaptorStrategy, [config: "foo"]}
         ]}
      )

      assert {:ok, result} = Lightning.Adaptors.all(adaptors_name)

      assert result == [
               "@openfn/language-foo",
               "@openfn/language-bar"
             ]
    end

    test "returns list of adaptor names using default name" do
      # Use a different port/name to avoid conflicts
      temp_name = Lightning.Adaptors

      start_supervised!(
        {Lightning.Adaptors,
         [
           name: temp_name,
           strategy: {MockAdaptorStrategy, [config: "foo"]}
         ]}
      )

      # Wait for supervisor to fully start
      Process.sleep(100)

      assert {:ok, result} = Lightning.Adaptors.all()

      assert result == [
               "@openfn/language-foo",
               "@openfn/language-bar"
             ]
    end

    test "caches results in the cachex process" do
      adaptors_name = :"adaptors_cache_test_#{:rand.uniform(10000)}"

      start_supervised!(
        {Lightning.Adaptors,
         [
           name: adaptors_name,
           strategy: {MockAdaptorStrategy, [config: "foo"]}
         ]}
      )

      assert {:ok, result} = Lightning.Adaptors.all(adaptors_name)
      assert result == ["@openfn/language-foo", "@openfn/language-bar"]

      config = Lightning.Adaptors.config(adaptors_name)

      {:ok, cached_result} = Cachex.get(config[:cache], :adaptors)
      assert cached_result == ["@openfn/language-foo", "@openfn/language-bar"]
    end
  end

  describe "versions_for/2 with registry-based API" do
    test "returns versions for a cached adaptor" do
      adaptors_name = :"versions_test_#{:rand.uniform(10000)}"

      start_supervised!(
        {Lightning.Adaptors,
         [
           name: adaptors_name,
           strategy: {MockAdaptorStrategy, [config: "foo"]}
         ]}
      )

      # Populate cache first
      Lightning.Adaptors.all(adaptors_name)

      # Test versions_for
      {:ok, versions} =
        Lightning.Adaptors.versions_for(adaptors_name, "@openfn/language-foo")

      expected_versions = %{
        "1.0.0" => %{"version" => "1.0.0"},
        "2.0.0" => %{"version" => "2.0.0"},
        "2.1.0" => %{"version" => "2.1.0"}
      }

      assert versions == expected_versions

      {:ok, versions} =
        Lightning.Adaptors.versions_for(adaptors_name, "@openfn/language-bar")

      expected_versions = %{
        "2.0.0" => %{"version" => "2.0.0"},
        "2.1.0" => %{"version" => "2.1.0"},
        "latest" => %{"version" => "2.1.0"}
      }

      assert versions == expected_versions
    end

    test "returns versions using default instance" do
      temp_name = :"default_versions_test_#{:rand.uniform(10000)}"

      start_supervised!(
        {Lightning.Adaptors,
         [
           name: Lightning.Adaptors,
           strategy: {MockAdaptorStrategy, [config: "foo"]}
         ]},
        id: temp_name
      )

      # Test versions_for with default instance (single argument)
      {:ok, versions} = Lightning.Adaptors.versions_for("@openfn/language-foo")

      assert versions == %{
               "1.0.0" => %{"version" => "1.0.0"},
               "2.0.0" => %{"version" => "2.0.0"},
               "2.1.0" => %{"version" => "2.1.0"}
             }
    end

    test "returns nil for non-existent adaptor" do
      adaptors_name = :"versions_not_found_test_#{:rand.uniform(10000)}"

      start_supervised!(
        {Lightning.Adaptors,
         [
           name: adaptors_name,
           strategy: {MockAdaptorStrategy, [config: "foo"]}
         ]}
      )

      # Populate cache first
      Lightning.Adaptors.all(adaptors_name)

      # Test versions_for with non-existent adaptor
      versions =
        Lightning.Adaptors.versions_for(
          adaptors_name,
          "@openfn/language-nonexistent"
        )

      assert {:error, :not_found} = versions
    end

    test "populates cache if not already populated" do
      adaptors_name = :"versions_auto_populate_test_#{:rand.uniform(10000)}"

      start_supervised!(
        {Lightning.Adaptors,
         [
           name: adaptors_name,
           strategy: {MockAdaptorStrategy, [config: "foo"]}
         ]}
      )

      config = Lightning.Adaptors.config(adaptors_name)

      {:ok, nil} = Cachex.get(config[:cache], "@openfn/language-foo:versions")

      # Call versions_for without calling all/1 first
      {:ok, versions} =
        Lightning.Adaptors.versions_for(adaptors_name, "@openfn/language-foo")

      expected_versions = %{
        "1.0.0" => %{"version" => "1.0.0"},
        "2.0.0" => %{"version" => "2.0.0"},
        "2.1.0" => %{"version" => "2.1.0"}
      }

      assert versions == expected_versions

      assert {:ok, ^expected_versions} =
               Cachex.get(config[:cache], "@openfn/language-foo:versions")
    end
  end

  describe "latest_for/2 with registry-based API" do
    test "returns latest version for a cached adaptor" do
      adaptors_name = :"latest_test_#{:rand.uniform(10000)}"

      start_supervised!(
        {Lightning.Adaptors,
         [
           name: adaptors_name,
           strategy: {MockAdaptorStrategy, [config: "foo"]}
         ]}
      )

      # Test latest_for
      {:ok, nil} =
        Lightning.Adaptors.latest_for(adaptors_name, "@openfn/language-foo")

      assert {:ok, %{"version" => "2.1.0"}} =
               Lightning.Adaptors.latest_for(
                 adaptors_name,
                 "@openfn/language-bar"
               )
    end

    test "returns latest version using default instance" do
      temp_name = :"default_latest_test_#{:rand.uniform(10000)}"

      start_supervised!(
        {Lightning.Adaptors,
         [
           name: Lightning.Adaptors,
           strategy: {MockAdaptorStrategy, [config: "foo"]}
         ]},
        id: temp_name
      )

      # Test latest_for with default instance (single argument)
      assert {:ok, %{"version" => "2.1.0"}} =
               Lightning.Adaptors.latest_for("@openfn/language-bar")
    end

    test "returns nil for non-existent adaptor" do
      adaptors_name = :"latest_not_found_test_#{:rand.uniform(10000)}"

      start_supervised!(
        {Lightning.Adaptors,
         [
           name: adaptors_name,
           strategy: {MockAdaptorStrategy, [config: "foo"]}
         ]}
      )

      # Populate cache first
      Lightning.Adaptors.all(adaptors_name)

      # Test latest_for with non-existent adaptor
      latest =
        Lightning.Adaptors.latest_for(
          adaptors_name,
          "@openfn/language-nonexistent"
        )

      assert {:error, :not_found} = latest
    end

    test "populates a single adaptors cache if not already populated" do
      adaptors_name = :"latest_auto_populate_test_#{:rand.uniform(10000)}"

      start_supervised!(
        {Lightning.Adaptors,
         [
           name: adaptors_name,
           strategy: {MockAdaptorStrategy, [config: "foo"]}
         ]}
      )

      # Call latest_for without calling all/1 first
      {:ok, latest} =
        Lightning.Adaptors.latest_for(adaptors_name, "@openfn/language-bar")

      assert latest == %{"version" => "2.1.0"}

      # Verify that the cache was populated
      config = Lightning.Adaptors.config(adaptors_name)

      {:ok, cached_latest} =
        Cachex.get(config[:cache], "@openfn/language-bar@latest")

      assert cached_latest == %{"version" => "2.1.0"}
    end
  end

  describe "cache persistence with registry-based API" do
    test "save_cache/1 saves cache to disk when persist_path is configured" do
      # Create a temporary file for testing
      cache_path =
        Path.join(System.tmp_dir!(), "test_cache_#{:rand.uniform(1000)}.bin")

      adaptors_name = :"persistence_save_test_#{:rand.uniform(10000)}"

      start_supervised!(
        {Lightning.Adaptors,
         [
           name: adaptors_name,
           strategy: {MockAdaptorStrategy, [config: "foo"]},
           persist_path: cache_path
         ]}
      )

      # Populate the cache
      Lightning.Adaptors.all(adaptors_name)

      # Save the cache
      assert Lightning.Adaptors.save_cache(adaptors_name) == :ok

      # Verify file was created
      assert File.exists?(cache_path)

      # Cleanup
      File.rm!(cache_path)
    end

    test "restore_cache/1 restores cache from disk when persist_path is configured" do
      cache_path =
        Path.join(System.tmp_dir!(), "test_cache_#{:rand.uniform(1000)}.bin")

      adaptors_name = :"persistence_restore_test_#{:rand.uniform(10000)}"

      start_supervised!(
        {Lightning.Adaptors,
         [
           name: adaptors_name,
           strategy: {MockAdaptorStrategy, [config: "foo"]},
           persist_path: cache_path
         ]}
      )

      # First, populate and save cache
      Lightning.Adaptors.all(adaptors_name)
      config = Lightning.Adaptors.config(adaptors_name)
      Lightning.Adaptors.save_cache(adaptors_name)

      # Clear the cache
      Cachex.clear(config[:cache])

      # Verify cache is empty
      {:ok, nil} = Cachex.get(config[:cache], :adaptors)

      # Restore from disk
      assert Lightning.Adaptors.restore_cache(adaptors_name) == :ok

      # Verify cache was restored
      {:ok, cached_adaptors} = Cachex.get(config[:cache], :adaptors)
      assert cached_adaptors == ["@openfn/language-foo", "@openfn/language-bar"]

      # Cleanup
      File.rm!(cache_path)
    end

    test "clear_persisted_cache/1 removes cache file when persist_path is configured" do
      cache_path =
        Path.join(System.tmp_dir!(), "test_cache_#{:rand.uniform(1000)}.bin")

      adaptors_name = :"persistence_clear_test_#{:rand.uniform(10000)}"

      start_supervised!(
        {Lightning.Adaptors,
         [
           name: adaptors_name,
           strategy: {MockAdaptorStrategy, [config: "foo"]},
           persist_path: cache_path
         ]}
      )

      # Create and save cache
      Lightning.Adaptors.all(adaptors_name)
      Lightning.Adaptors.save_cache(adaptors_name)

      # Verify file exists
      assert File.exists?(cache_path)

      # Clear persisted cache
      assert Lightning.Adaptors.clear_persisted_cache(adaptors_name) == :ok

      # Verify file was deleted
      refute File.exists?(cache_path)
    end

    # test "all/1 automatically saves cache after populating when persist_path is configured" do
    #   cache_path =
    #     Path.join(System.tmp_dir!(), "test_cache_#{:rand.uniform(1000)}.bin")

    #   adaptors_name = :"persistence_auto_save_test_#{:rand.uniform(10000)}"

    #   start_supervised!(
    #     {Lightning.Adaptors,
    #      [
    #        name: adaptors_name,
    #        strategy: {MockAdaptorStrategy, [config: "foo"]},
    #        persist_path: cache_path
    #      ]}
    #   )

    #   # Call all/1 which should populate and save cache
    #   result = Lightning.Adaptors.all(adaptors_name)
    #   assert {:ok, result} = result
    #   assert result == ["@openfn/language-foo", "@openfn/language-bar"]

    #   # Verify file was created
    #   assert File.exists?(cache_path)

    #   # Cleanup
    #   File.rm!(cache_path)
    # end
  end
end
