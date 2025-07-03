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
      cache_path =
        Path.join(System.tmp_dir!(), "test_cache_#{:rand.uniform(1000)}.bin")

      # Configuration passed explicitly - no Application.get_env used
      config = [
        name: :explicit_config_test,
        strategy: {MockAdaptorStrategy, [user: "test"]},
        persist_path: cache_path,
        # Fast interval for testing
        warm_interval: :timer.seconds(1)
      ]

      try do
        # Create a cache file with test data
        create_test_cache_file(cache_path)

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

    test "cache restoration works with explicit config" do
      cache_path =
        Path.join(System.tmp_dir!(), "cache_test_#{:rand.uniform(1000)}.bin")

      # First, create a cache file with test data
      create_test_cache_file(cache_path)

      config = [
        name: :cache_test,
        strategy: {MockAdaptorStrategy, [user: "test"]},
        persist_path: cache_path,
        warm_interval: :timer.minutes(5)
      ]

      try do
        {:ok, _pid} = start_supervised({Lightning.Adaptors.Supervisor, config})

        # Wait for initialization and cache restoration
        Process.sleep(500)

        # Should be able to make calls with restored cache
        assert {:ok, adaptors} = Lightning.Adaptors.all(:cache_test)
        assert is_list(adaptors)
        assert "@openfn/language-foo" in adaptors
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
      Application.put_env(:lightning_test, TestAdaptors,
        strategy: {MockAdaptorStrategy, [user: "facade_test"]},
        warm_interval: :timer.seconds(1)
      )

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

  # Helper function to create test cache file
  defp create_test_cache_file(path) do
    # Use data that matches MockAdaptorStrategy from test/support
    test_pairs = [
      {"adaptors", ["@openfn/language-foo", "@openfn/language-bar"]},
      {"@openfn/language-foo:versions",
       %{
         "1.0.0" => %{"version" => "1.0.0"},
         "2.0.0" => %{"version" => "2.0.0"},
         "2.1.0" => %{"version" => "2.1.0"}
       }},
      {"@openfn/language-bar:versions",
       %{
         "2.0.0" => %{"version" => "2.0.0"},
         "2.1.0" => %{"version" => "2.1.0"},
         "latest" => %{"version" => "2.1.0"}
       }}
    ]

    binary_data = :erlang.term_to_binary(test_pairs)
    File.write!(path, binary_data)
  end
end
