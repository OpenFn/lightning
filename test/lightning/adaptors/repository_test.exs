defmodule Lightning.Adaptors.RepositoryTest do
  use ExUnit.Case, async: true

  alias Lightning.Adaptors.Repository

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
    def fetch_credential_schema(_adaptor_name),
      do: {:error, :not_implemented}

    @impl true
    def fetch_icon(_adaptor_name, _version), do: {:error, :not_implemented}
  end

  describe "all/1" do
    test "returns list of adaptor names" do
      start_supervised!({Cachex, [:repository_adaptors_test, []]})

      config = %{
        strategy: {MockAdaptorStrategy, [config: "foo"]},
        cache: :repository_adaptors_test
      }

      assert {:ok, result} = Repository.all(config)

      assert result == [
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
      {:ok, result} = Repository.all(config)
      assert result == ["@openfn/language-foo", "@openfn/language-bar"]

      # Query the cache directly to verify the data is stored
      {:ok, cached_result} = Cachex.get(:repository_cache_test, "adaptors")
      assert cached_result == ["@openfn/language-foo", "@openfn/language-bar"]
    end

    test "handles strategy module without config tuple" do
      start_supervised!({Cachex, [:repository_simple_strategy_test, []]})

      config = %{
        # Module only, not tuple
        strategy: MockAdaptorStrategy,
        cache: :repository_simple_strategy_test
      }

      {:ok, result} = Repository.all(config)
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

      assert {:ok, nil} =
               Cachex.get(
                 :repository_versions_test,
                 "@openfn/language-foo:versions"
               )

      # Test versions_for
      {:ok, versions} = Repository.versions_for(config, "@openfn/language-foo")

      expected_versions = %{
        "1.0.0" => %{"version" => "1.0.0"},
        "2.0.0" => %{"version" => "2.0.0"},
        "2.1.0" => %{"version" => "2.1.0"}
      }

      assert versions == expected_versions

      {:ok, cached_versions} =
        Cachex.get(:repository_versions_test, "@openfn/language-foo:versions")

      assert cached_versions == expected_versions
    end

    test "returns nil for non-existent adaptor" do
      start_supervised!({Cachex, [:repository_versions_not_found_test, []]})

      config = %{
        strategy: {MockAdaptorStrategy, [config: "foo"]},
        cache: :repository_versions_not_found_test
      }

      # Test versions_for with non-existent adaptor
      assert {:error, :not_found} =
               Repository.versions_for(config, "@openfn/language-nonexistent")
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

      # TODO: make a special case to do a semver comparison, but be sure
      # to add a warning if this was necessary
      # {:ok, latest} = Repository.latest_for(config, "@openfn/language-foo")
      # assert latest == %{"version" => "1.0.0"}

      {:ok, latest} = Repository.latest_for(config, "@openfn/language-bar")
      assert latest == %{"version" => "2.1.0"}
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
      assert {:error, :not_found} =
               Repository.latest_for(config, "@openfn/language-nonexistent")
    end

    test "populates cache if not already populated" do
      start_supervised!({Cachex, [:repository_latest_auto_populate_test, []]})

      config = %{
        strategy: {MockAdaptorStrategy, [config: "foo"]},
        cache: :repository_latest_auto_populate_test
      }

      # Call latest_for without calling all/1 first
      {:ok, latest} = Repository.latest_for(config, "@openfn/language-bar")
      assert latest == %{"version" => "2.1.0"}

      # Verify that the cache was populated
      {:ok, cached_latest} =
        Cachex.get(config[:cache], "@openfn/language-bar@latest")

      assert cached_latest == %{"version" => "2.1.0"}
    end
  end
end
