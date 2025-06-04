defmodule MockAdaptorStrategy do
  @behaviour Lightning.Adaptors.Strategy
  def fetch_packages(_config) do
    {:ok,
     [
       %Lightning.Adaptors.Package{
         name: "@openfn/language-foo",
         repo: "https://github.com/openfn/foo",
         latest: "1.0.0",
         versions: [%{version: "1.0.0"}]
       },
       %Lightning.Adaptors.Package{
         name: "@openfn/language-bar",
         repo: "https://github.com/openfn/bar",
         latest: "2.1.0",
         versions: [%{version: "2.0.0"}, %{version: "2.1.0"}]
       }
     ]}
  end

  def fetch_credential_schema(_adaptor_name, _version) do
    {:error, :not_implemented}
  end

  def fetch_icon(_adaptor_name, _version) do
    {:error, :not_implemented}
  end
end

defmodule Lightning.AdaptorsTest do
  use ExUnit.Case, async: true

  describe "all/1" do
    test "returns list of adaptor names" do
      start_supervised!({Cachex, [:adaptors_test, []]})

      assert Lightning.Adaptors.all(%{
               strategy: {MockAdaptorStrategy, [config: "foo"]},
               cache: :adaptors_test
             }) == ["@openfn/language-foo", "@openfn/language-bar"]
    end

    test "caches results in the specified cachex process" do
      start_supervised!({Cachex, [:adaptors_cache_test, []]})

      config = %{
        strategy: {MockAdaptorStrategy, [config: "foo"]},
        cache: :adaptors_cache_test
      }

      # Call all/1 to populate the cache
      result = Lightning.Adaptors.all(config)
      assert result == ["@openfn/language-foo", "@openfn/language-bar"]

      # Query the cache directly to verify the data is stored
      {:ok, cached_result} = Cachex.get(:adaptors_cache_test, :adaptors)
      assert cached_result == ["@openfn/language-foo", "@openfn/language-bar"]
    end

    test "caches individual adaptors for efficient lookup" do
      start_supervised!({Cachex, [:adaptors_individual_cache_test, []]})

      config = %{
        strategy: {MockAdaptorStrategy, [config: "foo"]},
        cache: :adaptors_individual_cache_test
      }

      # Call all/1 to populate the cache
      Lightning.Adaptors.all(config)

      # Verify individual adaptors are cached
      {:ok, foo_adaptor} =
        Cachex.get(:adaptors_individual_cache_test, "@openfn/language-foo")

      assert foo_adaptor.name == "@openfn/language-foo"
      assert foo_adaptor.latest == "1.0.0"
      assert foo_adaptor.versions == [%{version: "1.0.0"}]

      {:ok, bar_adaptor} =
        Cachex.get(:adaptors_individual_cache_test, "@openfn/language-bar")

      assert bar_adaptor.name == "@openfn/language-bar"
      assert bar_adaptor.latest == "2.1.0"
      assert bar_adaptor.versions == [%{version: "2.0.0"}, %{version: "2.1.0"}]
    end
  end

  describe "versions_for/2" do
    test "returns versions for a cached adaptor" do
      start_supervised!({Cachex, [:versions_test, []]})

      config = %{
        strategy: {MockAdaptorStrategy, [config: "foo"]},
        cache: :versions_test
      }

      # Populate cache first
      Lightning.Adaptors.all(config)

      # Test versions_for
      versions = Lightning.Adaptors.versions_for(config, "@openfn/language-foo")
      assert versions == [%{version: "1.0.0"}]

      versions = Lightning.Adaptors.versions_for(config, "@openfn/language-bar")
      assert versions == [%{version: "2.0.0"}, %{version: "2.1.0"}]
    end

    test "returns nil for non-existent adaptor" do
      start_supervised!({Cachex, [:versions_not_found_test, []]})

      config = %{
        strategy: {MockAdaptorStrategy, [config: "foo"]},
        cache: :versions_not_found_test
      }

      # Populate cache first
      Lightning.Adaptors.all(config)

      # Test versions_for with non-existent adaptor
      versions =
        Lightning.Adaptors.versions_for(config, "@openfn/language-nonexistent")

      assert versions == nil
    end

    test "populates cache if not already populated" do
      start_supervised!({Cachex, [:versions_auto_populate_test, []]})

      config = %{
        strategy: {MockAdaptorStrategy, [config: "foo"]},
        cache: :versions_auto_populate_test
      }

      # Call versions_for without calling all/1 first
      versions = Lightning.Adaptors.versions_for(config, "@openfn/language-foo")
      assert versions == [%{version: "1.0.0"}]

      # Verify that the cache was populated
      {:ok, cached_adaptors} =
        Cachex.get(:versions_auto_populate_test, :adaptors)

      assert cached_adaptors == ["@openfn/language-foo", "@openfn/language-bar"]
    end
  end

  describe "latest_for/2" do
    test "returns latest version for a cached adaptor" do
      start_supervised!({Cachex, [:latest_test, []]})

      config = %{
        strategy: {MockAdaptorStrategy, [config: "foo"]},
        cache: :latest_test
      }

      # Populate cache first
      Lightning.Adaptors.all(config)

      # Test latest_for
      latest = Lightning.Adaptors.latest_for(config, "@openfn/language-foo")
      assert latest == "1.0.0"

      latest = Lightning.Adaptors.latest_for(config, "@openfn/language-bar")
      assert latest == "2.1.0"
    end

    test "returns nil for non-existent adaptor" do
      start_supervised!({Cachex, [:latest_not_found_test, []]})

      config = %{
        strategy: {MockAdaptorStrategy, [config: "foo"]},
        cache: :latest_not_found_test
      }

      # Populate cache first
      Lightning.Adaptors.all(config)

      # Test latest_for with non-existent adaptor
      latest =
        Lightning.Adaptors.latest_for(config, "@openfn/language-nonexistent")

      assert latest == nil
    end

    test "populates cache if not already populated" do
      start_supervised!({Cachex, [:latest_auto_populate_test, []]})

      config = %{
        strategy: {MockAdaptorStrategy, [config: "foo"]},
        cache: :latest_auto_populate_test
      }

      # Call latest_for without calling all/1 first
      latest = Lightning.Adaptors.latest_for(config, "@openfn/language-bar")
      assert latest == "2.1.0"

      # Verify that the cache was populated
      {:ok, cached_adaptors} = Cachex.get(:latest_auto_populate_test, :adaptors)
      assert cached_adaptors == ["@openfn/language-foo", "@openfn/language-bar"]
    end
  end

  describe "cache persistence" do
    test "save_cache/1 saves cache to disk when persist_path is configured" do
      start_supervised!({Cachex, [:persistence_save_test, []]})

      # Create a temporary file for testing
      cache_path =
        Path.join(System.tmp_dir!(), "test_cache_#{:rand.uniform(1000)}.bin")

      config = %{
        strategy: {MockAdaptorStrategy, [config: "foo"]},
        cache: :persistence_save_test,
        persist_path: cache_path
      }

      # Populate the cache
      Lightning.Adaptors.all(config)

      # Manually save the cache
      assert Lightning.Adaptors.save_cache(config) == :ok

      # Verify file was created
      assert File.exists?(cache_path)

      # Cleanup
      File.rm!(cache_path)
    end

    test "save_cache/1 returns :ok when persist_path is nil" do
      start_supervised!({Cachex, [:persistence_save_nil_test, []]})

      config = %{
        strategy: {MockAdaptorStrategy, [config: "foo"]},
        cache: :persistence_save_nil_test,
        persist_path: nil
      }

      assert Lightning.Adaptors.save_cache(config) == :ok
    end

    test "restore_cache/1 restores cache from disk when persist_path is configured" do
      start_supervised!({Cachex, [:persistence_restore_test, []]})

      cache_path =
        Path.join(System.tmp_dir!(), "test_cache_#{:rand.uniform(1000)}.bin")

      config = %{
        strategy: {MockAdaptorStrategy, [config: "foo"]},
        cache: :persistence_restore_test,
        persist_path: cache_path
      }

      # First, populate and save cache
      Lightning.Adaptors.all(config)
      Lightning.Adaptors.save_cache(config)

      # Clear the cache
      Cachex.clear(config[:cache])

      # Verify cache is empty
      {:ok, nil} = Cachex.get(config[:cache], :adaptors)

      # Restore from disk
      assert Lightning.Adaptors.restore_cache(config) == :ok

      # Verify cache was restored
      {:ok, cached_adaptors} = Cachex.get(config[:cache], :adaptors)
      assert cached_adaptors == ["@openfn/language-foo", "@openfn/language-bar"]

      # Cleanup
      File.rm!(cache_path)
    end

    test "restore_cache/1 returns :ok when no cache file exists" do
      start_supervised!({Cachex, [:persistence_restore_no_file_test, []]})

      cache_path = Path.join(System.tmp_dir!(), "non_existent_cache.bin")

      config = %{
        strategy: {MockAdaptorStrategy, [config: "foo"]},
        cache: :persistence_restore_no_file_test,
        persist_path: cache_path
      }

      assert Lightning.Adaptors.restore_cache(config) == :ok
    end

    test "restore_cache/1 returns :ok when persist_path is nil" do
      start_supervised!({Cachex, [:persistence_restore_nil_test, []]})

      config = %{
        strategy: {MockAdaptorStrategy, [config: "foo"]},
        cache: :persistence_restore_nil_test,
        persist_path: nil
      }

      assert Lightning.Adaptors.restore_cache(config) == :ok
    end

    test "clear_persisted_cache/1 removes cache file when persist_path is configured" do
      start_supervised!({Cachex, [:persistence_clear_test, []]})

      cache_path =
        Path.join(System.tmp_dir!(), "test_cache_#{:rand.uniform(1000)}.bin")

      config = %{
        strategy: {MockAdaptorStrategy, [config: "foo"]},
        cache: :persistence_clear_test,
        persist_path: cache_path
      }

      # Create and save cache
      Lightning.Adaptors.all(config)
      Lightning.Adaptors.save_cache(config)

      # Verify file exists
      assert File.exists?(cache_path)

      # Clear persisted cache
      assert Lightning.Adaptors.clear_persisted_cache(config) == :ok

      # Verify file was deleted
      refute File.exists?(cache_path)
    end

    test "clear_persisted_cache/1 returns :ok when persist_path is nil" do
      config = %{
        persist_path: nil
      }

      assert Lightning.Adaptors.clear_persisted_cache(config) == :ok
    end

    test "all/1 automatically restores cache on first access when persist_path is configured" do
      start_supervised!({Cachex, [:persistence_auto_restore_test, []]})

      cache_path =
        Path.join(System.tmp_dir!(), "test_cache_#{:rand.uniform(10000)}.bin")

      config = %{
        strategy: {MockAdaptorStrategy, [config: "foo"]},
        cache: :persistence_auto_restore_test,
        persist_path: cache_path
      }

      # First, populate and save cache
      Lightning.Adaptors.all(config)
      Lightning.Adaptors.save_cache(config)

      # Clear the in-memory cache to simulate app restart
      Cachex.clear(config[:cache])

      # Verify cache is empty
      {:ok, nil} = Cachex.get(config[:cache], :adaptors)

      # Now call all/1 again - it should automatically restore from disk
      result = Lightning.Adaptors.all(config)
      assert result == ["@openfn/language-foo", "@openfn/language-bar"]

      # Verify individual adaptors were also restored
      {:ok, foo_adaptor} = Cachex.get(config[:cache], "@openfn/language-foo")
      assert foo_adaptor.name == "@openfn/language-foo"

      # Cleanup
      File.rm!(cache_path)
    end

    test "all/1 automatically saves cache after populating when persist_path is configured" do
      start_supervised!({Cachex, [:persistence_auto_save_test, []]})

      cache_path =
        Path.join(System.tmp_dir!(), "test_cache_#{:rand.uniform(1000)}.bin")

      config = %{
        strategy: {MockAdaptorStrategy, [config: "foo"]},
        cache: :persistence_auto_save_test,
        persist_path: cache_path
      }

      # Call all/1 which should populate and save cache
      result = Lightning.Adaptors.all(config)
      assert result == ["@openfn/language-foo", "@openfn/language-bar"]

      # Verify file was created
      assert File.exists?(cache_path)

      # Cleanup
      File.rm!(cache_path)
    end
  end
end
