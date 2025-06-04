defmodule Lightning.Adaptors.RepositoryTest do
  use ExUnit.Case, async: true

  alias Lightning.Adaptors.Repository

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

    def validate_config(_config), do: {:ok, []}

    def fetch_credential_schema(_adaptor_name, _version),
      do: {:error, :not_implemented}

    def fetch_icon(_adaptor_name, _version), do: {:error, :not_implemented}
  end

  describe "all/1" do
    test "returns list of adaptor names" do
      start_supervised!({Cachex, [:repository_adaptors_test, []]})

      config = %{
        strategy: {MockAdaptorStrategy, [config: "foo"]},
        cache: :repository_adaptors_test
      }

      assert Repository.all(config) == [
               "@openfn/language-foo",
               "@openfn/language-bar"
             ]
    end

    test "caches results in the specified cachex process" do
      start_supervised!({Cachex, [:repository_cache_test, []]})

      config = %{
        strategy: {MockAdaptorStrategy, [config: "foo"]},
        cache: :repository_cache_test
      }

      # Call all/1 to populate the cache
      result = Repository.all(config)
      assert result == ["@openfn/language-foo", "@openfn/language-bar"]

      # Query the cache directly to verify the data is stored
      {:ok, cached_result} = Cachex.get(:repository_cache_test, :adaptors)
      assert cached_result == ["@openfn/language-foo", "@openfn/language-bar"]
    end

    test "caches individual adaptors for efficient lookup" do
      start_supervised!({Cachex, [:repository_individual_cache_test, []]})

      config = %{
        strategy: {MockAdaptorStrategy, [config: "foo"]},
        cache: :repository_individual_cache_test
      }

      # Call all/1 to populate the cache
      Repository.all(config)

      # Verify individual adaptors are cached
      {:ok, foo_adaptor} =
        Cachex.get(:repository_individual_cache_test, "@openfn/language-foo")

      assert foo_adaptor.name == "@openfn/language-foo"
      assert foo_adaptor.latest == "1.0.0"
      assert foo_adaptor.versions == [%{version: "1.0.0"}]

      {:ok, bar_adaptor} =
        Cachex.get(:repository_individual_cache_test, "@openfn/language-bar")

      assert bar_adaptor.name == "@openfn/language-bar"
      assert bar_adaptor.latest == "2.1.0"
      assert bar_adaptor.versions == [%{version: "2.0.0"}, %{version: "2.1.0"}]
    end

    test "handles strategy module without config tuple" do
      start_supervised!({Cachex, [:repository_simple_strategy_test, []]})

      config = %{
        # Module only, not tuple
        strategy: MockAdaptorStrategy,
        cache: :repository_simple_strategy_test
      }

      result = Repository.all(config)
      assert result == ["@openfn/language-foo", "@openfn/language-bar"]
    end
  end

  describe "versions_for/2" do
    test "returns versions for a cached adaptor" do
      start_supervised!({Cachex, [:repository_versions_test, []]})

      config = %{
        strategy: {MockAdaptorStrategy, [config: "foo"]},
        cache: :repository_versions_test
      }

      # Populate cache first
      Repository.all(config)

      # Test versions_for
      versions = Repository.versions_for(config, "@openfn/language-foo")
      assert versions == [%{version: "1.0.0"}]

      versions = Repository.versions_for(config, "@openfn/language-bar")
      assert versions == [%{version: "2.0.0"}, %{version: "2.1.0"}]
    end

    test "returns nil for non-existent adaptor" do
      start_supervised!({Cachex, [:repository_versions_not_found_test, []]})

      config = %{
        strategy: {MockAdaptorStrategy, [config: "foo"]},
        cache: :repository_versions_not_found_test
      }

      # Populate cache first
      Repository.all(config)

      # Test versions_for with non-existent adaptor
      versions = Repository.versions_for(config, "@openfn/language-nonexistent")
      assert versions == nil
    end

    test "populates cache if not already populated" do
      start_supervised!({Cachex, [:repository_versions_auto_populate_test, []]})

      config = %{
        strategy: {MockAdaptorStrategy, [config: "foo"]},
        cache: :repository_versions_auto_populate_test
      }

      # Call versions_for without calling all/1 first
      versions = Repository.versions_for(config, "@openfn/language-foo")
      assert versions == [%{version: "1.0.0"}]

      # Verify that the cache was populated
      {:ok, cached_adaptors} =
        Cachex.get(:repository_versions_auto_populate_test, :adaptors)

      assert cached_adaptors == ["@openfn/language-foo", "@openfn/language-bar"]
    end
  end

  describe "latest_for/2" do
    test "returns latest version for a cached adaptor" do
      start_supervised!({Cachex, [:repository_latest_test, []]})

      config = %{
        strategy: {MockAdaptorStrategy, [config: "foo"]},
        cache: :repository_latest_test
      }

      # Populate cache first
      Repository.all(config)

      # Test latest_for
      latest = Repository.latest_for(config, "@openfn/language-foo")
      assert latest == "1.0.0"

      latest = Repository.latest_for(config, "@openfn/language-bar")
      assert latest == "2.1.0"
    end

    test "returns nil for non-existent adaptor" do
      start_supervised!({Cachex, [:repository_latest_not_found_test, []]})

      config = %{
        strategy: {MockAdaptorStrategy, [config: "foo"]},
        cache: :repository_latest_not_found_test
      }

      # Populate cache first
      Repository.all(config)

      # Test latest_for with non-existent adaptor
      latest = Repository.latest_for(config, "@openfn/language-nonexistent")
      assert latest == nil
    end

    test "populates cache if not already populated" do
      start_supervised!({Cachex, [:repository_latest_auto_populate_test, []]})

      config = %{
        strategy: {MockAdaptorStrategy, [config: "foo"]},
        cache: :repository_latest_auto_populate_test
      }

      # Call latest_for without calling all/1 first
      latest = Repository.latest_for(config, "@openfn/language-bar")
      assert latest == "2.1.0"

      # Verify that the cache was populated
      {:ok, cached_adaptors} =
        Cachex.get(:repository_latest_auto_populate_test, :adaptors)

      assert cached_adaptors == ["@openfn/language-foo", "@openfn/language-bar"]
    end
  end
end
