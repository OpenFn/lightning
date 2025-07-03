defmodule Lightning.Adaptors.IntegrationTest do
  @moduledoc """
  Integration tests demonstrating configuration passing without Application.get_env.
  """
  use ExUnit.Case, async: false

  setup do
    # Start the Registry before each test
    start_supervised!(Lightning.Adaptors.Registry)
    :ok
  end

  describe "configuration passing" do
    test "passes config explicitly without Application.get_env" do
      cache_path = Path.join(System.tmp_dir!(), "test_cache_#{:rand.uniform(1000)}.bin")

      # Configuration passed explicitly - no Application.get_env used
      config = [
        name: :explicit_config_test,
        strategy: {MockAdaptorStrategy, [user: "test"]},
        persist_path: cache_path,
        offline_mode: true,  # Use offline mode to avoid network calls in tests
        warm_interval: :timer.seconds(1)  # Fast interval for testing
      ]

      try do
        # Create an empty cache file for offline mode
        File.touch!(cache_path)

        {:ok, _pid} = start_supervised({Lightning.Adaptors.Supervisor, config})

        # Wait for initialization
        Process.sleep(200)

        # Should be able to call functions
        assert {:ok, adaptors} = Lightning.Adaptors.all(:explicit_config_test)
        assert is_list(adaptors)
      after
        if File.exists?(cache_path), do: File.rm!(cache_path)
      end
    end

    test "offline mode works with explicit config" do
      cache_path = Path.join(System.tmp_dir!(), "offline_test_#{:rand.uniform(1000)}.bin")

      # First, create a cache file
      File.touch!(cache_path)

      config = [
        name: :offline_test,
        strategy: {MockAdaptorStrategy, [user: "test"]},
        persist_path: cache_path,
        offline_mode: true,  # Explicit offline mode
        warm_interval: :timer.minutes(5)
      ]

      try do
        {:ok, _pid} = start_supervised({Lightning.Adaptors.Supervisor, config})

        # Wait for initialization
        Process.sleep(200)

        # In offline mode, should still be able to make calls
        # (though cache might be empty since we created an empty file)
        assert {:ok, _} = Lightning.Adaptors.all(:offline_test)
      after
        if File.exists?(cache_path), do: File.rm!(cache_path)
      end
    end

    test "facade module with explicit config" do
      # Define a facade module for testing
      defmodule TestAdaptors do
        use Lightning.Adaptors.Service, otp_app: :lightning_test
      end

      # Set up config for the facade
      Application.put_env(:lightning_test, TestAdaptors, [
        strategy: {MockAdaptorStrategy, [user: "facade_test"]},
        offline_mode: false,  # Default online mode - will attempt to warm
        warm_interval: :timer.seconds(1)
      ])

      try do
        {:ok, _pid} = start_supervised(TestAdaptors)

        # Wait for initialization
        Process.sleep(200)

        # Should work with facade functions
        assert {:ok, adaptors} = TestAdaptors.all()
        assert is_list(adaptors)
      after
        Application.delete_env(:lightning_test, TestAdaptors)
      end
    end
  end

  # Mock strategy for testing
  defmodule MockAdaptorStrategy do
    @behaviour Lightning.Adaptors.Strategy

    @impl true
    def fetch_packages(_config) do
      {:ok, ["@openfn/language-test", "@openfn/language-mock"]}
    end

    @impl true
    def fetch_versions(_config, "@openfn/language-test") do
      {:ok, %{"1.0.0" => %{"version" => "1.0.0"}, "1.1.0" => %{"version" => "1.1.0"}}}
    end

    @impl true
    def fetch_versions(_config, "@openfn/language-mock") do
      {:ok, %{"2.0.0" => %{"version" => "2.0.0"}}}
    end

    @impl true
    def fetch_versions(_config, _name) do
      {:error, :not_found}
    end

    @impl true
    def fetch_configuration_schema("@openfn/language-test") do
      {:ok, %{"type" => "object", "properties" => %{"test" => %{"type" => "string"}}}}
    end

    @impl true
    def fetch_configuration_schema("@openfn/language-mock") do
      {:ok, %{"type" => "object", "properties" => %{"mock" => %{"type" => "boolean"}}}}
    end

    @impl true
    def fetch_configuration_schema(_name) do
      {:error, :not_found}
    end

    @impl true
    def fetch_icon(_name, _version) do
      {:error, :not_implemented}
    end
  end
end
