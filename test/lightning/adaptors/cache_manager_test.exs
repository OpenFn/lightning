defmodule Lightning.Adaptors.CacheManagerTest do
  use ExUnit.Case, async: false

  alias Lightning.Adaptors.CacheManager

  setup do
    # Start the Registry before each test
    start_supervised!(Lightning.Adaptors.Registry)
    :ok
  end

  describe "supervisor behavior" do
    test "starts as supervisor and manages Cachex as child" do
      config = %{
        name: :supervisor_test,
        cache: :supervisor_cache,
        strategy: {MockStrategy, []},
        persist_path: nil,
        warm_interval: :timer.minutes(5)
      }

      {:ok, pid} = CacheManager.start_link(config)

      # Give it time to initialize
      Process.sleep(100)

      # Should still be running
      assert Process.alive?(pid)

      # Check that Cachex is running as a child
      children = Supervisor.which_children(pid)
      assert length(children) == 1

      # The child should be Cachex
      [{_, child_pid, :supervisor, [Cachex]}] = children
      assert Process.alive?(child_pid)
    end

    test "determines warmers correctly when cache file exists" do
      cache_path = create_temp_cache_file_with_data()

      config = %{
        name: :file_exists_test,
        cache: :file_cache,
        strategy: {MockStrategy, []},
        persist_path: cache_path,
        warm_interval: :timer.minutes(5)
      }

      try do
        warmers = CacheManager.determine_warmers(config)

        # Should have both CacheRestorer and StrategyWarmer
        assert length(warmers) == 2

        # First warmer should be CacheRestorer (required)
        # Warmer tuple format: {:warmer, required, interval, module, state, async}
        assert elem(warmers |> Enum.at(0), 3) == Lightning.Adaptors.CacheRestorer
        assert elem(warmers |> Enum.at(0), 1) == true

        # Second warmer should be StrategyWarmer (optional)
        assert elem(warmers |> Enum.at(1), 3) == Lightning.Adaptors.Warmer
        assert elem(warmers |> Enum.at(1), 1) == false
      after
        File.rm(cache_path)
      end
    end

    test "determines warmers correctly when no cache file exists" do
      config = %{
        name: :no_file_test,
        cache: :no_file_cache,
        strategy: {MockStrategy, []},
        persist_path: nil,
        warm_interval: :timer.minutes(5)
      }

      warmers = CacheManager.determine_warmers(config)

      # Should have only StrategyWarmer
      assert length(warmers) == 1

      # Only warmer should be StrategyWarmer (required)
      # Warmer tuple format: {:warmer, required, interval, module, state, async}
      assert elem(warmers |> Enum.at(0), 3) == Lightning.Adaptors.Warmer
      assert elem(warmers |> Enum.at(0), 1) == true
    end

    test "starts successfully without cache file" do
      config = %{
        name: :no_cache_test,
        cache: :no_cache_cache,
        strategy: {MockStrategy, []},
        persist_path: nil,
        warm_interval: :timer.minutes(5)
      }

      {:ok, pid} = CacheManager.start_link(config)

      # Give it time to initialize
      Process.sleep(100)

      # Should still be running
      assert Process.alive?(pid)

      # Verify Cachex is running as child
      children = Supervisor.which_children(pid)
      assert length(children) == 1
      [{_, child_pid, :supervisor, [Cachex]}] = children
      assert Process.alive?(child_pid)

      # Verify the cache exists and is accessible
      assert {:ok, nil} = Cachex.get(:no_cache_cache, "nonexistent_key")
    end
  end

  describe "cache restoration" do
    test "restores cache from existing file using CacheRestorer" do
      cache_path = create_temp_cache_file_with_data()

      config = %{
        name: :restore_test,
        cache: :restore_cache,
        strategy: {MockStrategy, []},
        persist_path: cache_path,
        warm_interval: :timer.minutes(5)
      }

      try do
        # Start cache manager - should restore from file
        {:ok, _pid} = CacheManager.start_link(config)
        Process.sleep(500)

        # Check if cache was restored from file
        {:ok, test_value} = Cachex.get(:restore_cache, "test_key")
        assert test_value == "test_value"

        {:ok, adaptors} = Cachex.get(:restore_cache, "adaptors")
        assert adaptors == ["@openfn/language-test"]
      after
        File.rm(cache_path)
      end
    end
  end

  # Mock strategy for testing
  defmodule MockStrategy do
    @behaviour Lightning.Adaptors.Strategy

    @impl true
    def fetch_packages(_config) do
      {:ok, ["@openfn/language-test"]}
    end

    @impl true
    def fetch_versions(_config, _name) do
      {:ok, %{"1.0.0" => %{"version" => "1.0.0"}}}
    end

    @impl true
    def fetch_configuration_schema(_name) do
      {:ok, %{"type" => "object"}}
    end

    @impl true
    def fetch_icon(_name, _version) do
      {:error, :not_implemented}
    end
  end

  defp create_temp_cache_file_with_data do
    path = Path.join(System.tmp_dir!(), "test_cache_#{:rand.uniform(10000)}.bin")

    # Create test data that matches what the warmers would create
    test_pairs = [
      {"test_key", "test_value"},
      {"adaptors", ["@openfn/language-test"]},
      {"@openfn/language-test:versions", %{"1.0.0" => %{"version" => "1.0.0"}}},
      {"@openfn/language-test:schema", %{"type" => "object"}}
    ]

    binary_data = :erlang.term_to_binary(test_pairs)
    File.write!(path, binary_data)
    path
  end
end
