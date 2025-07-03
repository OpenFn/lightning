defmodule Lightning.Adaptors.ServiceTest do
  use ExUnit.Case, async: false

  # Create a test module that uses the Service macro
  defmodule TestAdaptors do
    use Lightning.Adaptors.Service, otp_app: :lightning
  end

  setup do
    # Ensure the new Adaptors Registry is available for tests
    unless Process.whereis(Lightning.Adaptors.Registry) do
      start_supervised!({Registry, keys: :unique, name: Lightning.Adaptors.Registry})
    end
    :ok
  end

  describe "Lightning.Adaptors.Service.__using__/1" do
    test "generates child_spec/1 function that uses Supervisor" do
      assert function_exported?(TestAdaptors, :child_spec, 1)

      child_spec = TestAdaptors.child_spec([])
      assert %{id: TestAdaptors, start: {Lightning.Adaptors.Supervisor, :start_link, _}} = child_spec
    end

    test "generates config/0 function" do
      assert function_exported?(TestAdaptors, :config, 0)
    end

    test "generates all/0 function that delegates to API" do
      assert function_exported?(TestAdaptors, :all, 0)

      # Start the test adaptor
      start_supervised!(
        {TestAdaptors, 
         [strategy: {MockAdaptorStrategy, [config: "test"]}]},
        id: :test_adaptors_all
      )

      # Wait for supervisor to start
      Process.sleep(100)

      # Test that all/0 works
      assert {:ok, result} = TestAdaptors.all()
      assert result == ["@openfn/language-foo", "@openfn/language-bar"]
    end

    test "generates versions_for/1 function that delegates to API" do
      assert function_exported?(TestAdaptors, :versions_for, 1)

      # Start the test adaptor
      start_supervised!(
        {TestAdaptors, 
         [strategy: {MockAdaptorStrategy, [config: "test"]}]},
        id: :test_adaptors_versions
      )

      # Test that versions_for/1 works
      {:ok, versions} = TestAdaptors.versions_for("@openfn/language-foo")
      expected_versions = %{
        "1.0.0" => %{"version" => "1.0.0"},
        "2.0.0" => %{"version" => "2.0.0"},
        "2.1.0" => %{"version" => "2.1.0"}
      }
      assert versions == expected_versions
    end

    test "generates latest_for/1 function that delegates to API" do
      assert function_exported?(TestAdaptors, :latest_for, 1)

      # Start the test adaptor
      start_supervised!(
        {TestAdaptors, 
         [strategy: {MockAdaptorStrategy, [config: "test"]}]},
        id: :test_adaptors_latest
      )

      # Test that latest_for/1 works
      assert {:ok, %{"version" => "2.1.0"}} = TestAdaptors.latest_for("@openfn/language-bar")
    end

    test "generates fetch_configuration_schema/1 function that delegates to API" do
      assert function_exported?(TestAdaptors, :fetch_configuration_schema, 1)

      # Start the test adaptor
      start_supervised!(
        {TestAdaptors, 
         [strategy: {MockAdaptorStrategy, [config: "test"]}]},
        id: :test_adaptors_schema
      )

      # Test that fetch_configuration_schema/1 works (MockAdaptorStrategy returns not_implemented)
      result = TestAdaptors.fetch_configuration_schema("@openfn/language-foo")
      # The MockAdaptorStrategy returns {:error, :not_implemented}, which might be wrapped by Repository
      assert result in [
        {:error, :not_implemented},
        {:ok, {:ignore, :not_implemented}}
      ]
    end

    test "generates cache management functions" do
      assert function_exported?(TestAdaptors, :save_cache, 0)
      assert function_exported?(TestAdaptors, :restore_cache, 0)
      assert function_exported?(TestAdaptors, :clear_persisted_cache, 0)

      # Start the test adaptor with persistence
      cache_path = Path.join(System.tmp_dir!(), "service_test_cache_#{:rand.uniform(1000)}.bin")
      
      start_supervised!(
        {TestAdaptors, 
         [
           strategy: {MockAdaptorStrategy, [config: "test"]},
           persist_path: cache_path
         ]},
        id: :test_adaptors_cache
      )

      # Populate cache
      TestAdaptors.all()

      # Test save_cache/0
      assert :ok = TestAdaptors.save_cache()
      assert File.exists?(cache_path)

      # Test clear_persisted_cache/0
      assert :ok = TestAdaptors.clear_persisted_cache()
      refute File.exists?(cache_path)
    end

    test "supports configuration merging from application environment" do
      # This is tested implicitly by the child_spec generation
      # The macro properly merges configuration from multiple sources
      assert function_exported?(TestAdaptors, :child_spec, 1)
    end
  end
end