defmodule MockAdaptorStrategy do
  @behaviour Lightning.Adaptors.Strategy
  def fetch_adaptors(_config) do
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
end
