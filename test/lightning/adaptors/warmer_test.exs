defmodule Lightning.Adaptors.WarmerTest do
  use ExUnit.Case, async: false

  import Cachex.Spec
  alias Lightning.Adaptors.Warmer

  setup do
    schemas = %{
      dhis2: %{
        "type" => "object",
        "properties" => %{
          "username" => %{"type" => "string"},
          "password" => %{"type" => "string"}
        }
      },
      success: %{
        "type" => "object",
        "properties" => %{"api_key" => %{"type" => "string"}}
      },
      foo: %{
        "type" => "object",
        "properties" => %{"token" => %{"type" => "string"}}
      },
      bar: %{
        "type" => "object",
        "properties" => %{"api_key" => %{"type" => "string"}}
      }
    }

    {:ok, schemas: schemas}
  end

  describe "execute/1" do
    defmodule MockStrategySuccess do
      @behaviour Lightning.Adaptors.Strategy

      @impl true
      def fetch_packages(_config) do
        {:ok, ["@openfn/language-dhis2"]}
      end

      @impl true
      def fetch_versions(_config, "@openfn/language-dhis2") do
        {:ok,
         %{
           "3.2.0" => %{"version" => "3.2.0"},
           "3.2.8" => %{"version" => "3.2.8"}
         }}
      end

      @impl true
      def fetch_configuration_schema("@openfn/language-dhis2") do
        dhis2_schema = %{
          "type" => "object",
          "properties" => %{
            "username" => %{"type" => "string"},
            "password" => %{"type" => "string"}
          }
        }

        {:ok, dhis2_schema}
      end

      def fetch_configuration_schema(_name),
        do: {:error, :not_found}

      @impl true
      def fetch_icon(_name, _version), do: {:error, :not_implemented}
    end

    defmodule MockStrategyPackageFailure do
      @behaviour Lightning.Adaptors.Strategy

      @impl true
      def fetch_packages(_config) do
        {:error, "Something bad happened"}
      end

      @impl true
      def fetch_versions(_config, _adaptor_name) do
        {:error, :not_found}
      end

      @impl true
      def fetch_configuration_schema(_name),
        do: {:error, :not_implemented}

      @impl true
      def fetch_icon(_name, _version), do: {:error, :not_implemented}
    end

    defmodule MockStrategyVersionFailure do
      @behaviour Lightning.Adaptors.Strategy

      @impl true
      def fetch_packages(_config) do
        {:ok, ["@openfn/language-dhis2"]}
      end

      @impl true
      def fetch_versions(_config, "@openfn/language-dhis2") do
        {:error, :version_fetch_failed}
      end

      @impl true
      def fetch_configuration_schema(_name),
        do: {:error, :not_implemented}

      @impl true
      def fetch_icon(_name, _version), do: {:error, :not_implemented}
    end

    test "successfully caches adaptors list, individual adaptor versions, and configuration schemas",
         %{schemas: schemas} do
      config = %{
        strategy: {MockStrategySuccess, [config: "test"]},
        cache: :test_cache
      }

      assert {:ok, pairs} = Warmer.execute(config)

      assert {"adaptors", ["@openfn/language-dhis2"]} in pairs

      assert {"@openfn/language-dhis2:versions",
              %{
                "3.2.0" => %{"version" => "3.2.0"},
                "3.2.8" => %{"version" => "3.2.8"}
              }} in pairs

      assert {"@openfn/language-dhis2:schema", schemas.dhis2} in pairs
    end

    test "accepts strategy module without config tuple", %{schemas: schemas} do
      config = %{
        strategy: MockStrategySuccess,
        cache: :test_cache
      }

      assert {:ok, pairs} = Warmer.execute(config)

      assert {"adaptors", ["@openfn/language-dhis2"]} in pairs

      assert {"@openfn/language-dhis2:versions",
              %{
                "3.2.0" => %{"version" => "3.2.0"},
                "3.2.8" => %{"version" => "3.2.8"}
              }} in pairs

      assert {"@openfn/language-dhis2:schema", schemas.dhis2} in pairs
    end

    test "returns :ignore when fetch_packages fails" do
      config = %{
        strategy: {MockStrategyPackageFailure, []},
        cache: :test_cache
      }

      assert Warmer.execute(config) == :ignore
    end

    test "returns :ignore when strategy module raises exception" do
      config = %{
        strategy: {NonExistentModule, []},
        cache: :test_cache
      }

      assert Warmer.execute(config) == :ignore
    end

    test "successfully handles empty adaptor list" do
      defmodule EmptyAdaptorStrategy do
        @behaviour Lightning.Adaptors.Strategy

        @impl true
        def fetch_packages(_config) do
          {:ok, []}
        end

        @impl true
        def fetch_configuration_schema(_adaptor_name) do
          {:error, :not_implemented}
        end

        @impl true
        def fetch_icon(_adaptor_name, _version) do
          {:error, :not_implemented}
        end
      end

      config = %{
        strategy: {EmptyAdaptorStrategy, []},
        cache: :test_cache
      }

      assert {:ok, [{"adaptors", []}]} = Warmer.execute(config)
    end

    test "includes version and schema fetch failures in cache pairs" do
      config = %{
        strategy: {MockStrategyVersionFailure, []},
        cache: :test_cache
      }

      assert {:ok, pairs} = Warmer.execute(config)

      assert {"adaptors", ["@openfn/language-dhis2"]} in pairs

      assert {"@openfn/language-dhis2:versions",
              {:ignore, :version_fetch_failed}} in pairs

      assert {"@openfn/language-dhis2:schema", {:ignore, :not_implemented}} in pairs
    end

    test "handles mixed success and failure in version and schema fetching", %{
      schemas: schemas
    } do
      defmodule MixedVersionStrategy do
        @behaviour Lightning.Adaptors.Strategy

        @impl true
        def fetch_packages(_config) do
          {:ok, ["@openfn/language-success", "@openfn/language-failure"]}
        end

        @impl true
        def fetch_versions(_config, "@openfn/language-success") do
          {:ok, %{"1.0.0" => %{"version" => "1.0.0"}}}
        end

        @impl true
        def fetch_versions(_config, "@openfn/language-failure") do
          {:error, :fetch_failed}
        end

        @impl true
        def fetch_configuration_schema("@openfn/language-success") do
          success_schema = %{
            "type" => "object",
            "properties" => %{"api_key" => %{"type" => "string"}}
          }

          {:ok, success_schema}
        end

        def fetch_configuration_schema("@openfn/language-failure") do
          {:error, :schema_fetch_failed}
        end

        def fetch_configuration_schema(_name), do: {:error, :not_found}

        @impl true
        def fetch_icon(_name, _version), do: {:error, :not_implemented}
      end

      config = %{
        strategy: {MixedVersionStrategy, []},
        cache: :test_cache
      }

      assert {:ok, pairs} = Warmer.execute(config)

      assert {"adaptors",
              ["@openfn/language-success", "@openfn/language-failure"]} in pairs

      assert {"@openfn/language-success:versions",
              %{"1.0.0" => %{"version" => "1.0.0"}}} in pairs

      assert {"@openfn/language-failure:versions", {:ignore, :fetch_failed}} in pairs

      assert {"@openfn/language-success:schema", schemas.success} in pairs

      assert {"@openfn/language-failure:schema", {:ignore, :schema_fetch_failed}} in pairs
    end

    test "returns :ignore when module validation fails" do
      defmodule InvalidStrategy do
        # Missing @behaviour and required functions
      end

      config = %{
        strategy: {InvalidStrategy, []},
        cache: :test_cache
      }

      assert Warmer.execute(config) == :ignore
    end

    test "saves cache to disk when persist_path is configured", %{schemas: schemas} do
      persist_path = "/tmp/warmer_test_cache_#{:rand.uniform(10000)}.bin"

      config = %{
        strategy: {MockStrategySuccess, [config: "test"]},
        cache: :test_cache,
        persist_path: persist_path
      }

      # Ensure the file doesn't exist before the test
      File.rm(persist_path)

      assert {:ok, _pairs} = Warmer.execute(config)

      # Verify the file was created
      assert File.exists?(persist_path)

      # Verify the file contains the correct data
      {:ok, binary_data} = File.read(persist_path)
      pairs = :erlang.binary_to_term(binary_data)

      assert {"adaptors", ["@openfn/language-dhis2"]} in pairs
      assert {"@openfn/language-dhis2:schema", schemas.dhis2} in pairs

      # Clean up
      File.rm(persist_path)
    end

    test "does not save cache when persist_path is not configured" do
      config = %{
        strategy: {MockStrategySuccess, [config: "test"]},
        cache: :test_cache
      }

      assert {:ok, _pairs} = Warmer.execute(config)
      # No file should be created since persist_path is not configured
    end

    test "handles file write errors gracefully" do
      # Use a path that will cause a write error (non-existent directory)
      persist_path = "/nonexistent_directory/cache.bin"

      config = %{
        strategy: {MockStrategySuccess, [config: "test"]},
        cache: :test_cache,
        persist_path: persist_path
      }

      # Should still return {:ok, pairs} even if file write fails
      assert {:ok, _pairs} = Warmer.execute(config)

      # Verify the file was not created
      refute File.exists?(persist_path)
    end
  end

  describe "integration with Cachex" do
    defmodule CachexIntegrationStrategy do
      @behaviour Lightning.Adaptors.Strategy

      @impl true
      def fetch_packages(_config) do
        {:ok,
         [
           "@openfn/language-foo",
           "@openfn/language-bar"
         ]}
      end

      @impl true
      def fetch_versions(_config, "@openfn/language-foo") do
        {:ok,
         %{
           "1.0.0" => %{"version" => "1.0.0"}
         }}
      end

      @impl true
      def fetch_versions(_config, "@openfn/language-bar") do
        {:ok,
         %{
           "2.0.0" => %{"version" => "2.0.0"},
           "2.1.0" => %{"version" => "2.1.0"}
         }}
      end

      @impl true
      def fetch_configuration_schema("@openfn/language-foo") do
        foo_schema = %{
          "type" => "object",
          "properties" => %{"token" => %{"type" => "string"}}
        }

        {:ok, foo_schema}
      end

      def fetch_configuration_schema("@openfn/language-bar") do
        bar_schema = %{
          "type" => "object",
          "properties" => %{"api_key" => %{"type" => "string"}}
        }

        {:ok, bar_schema}
      end

      def fetch_configuration_schema(_adaptor_name),
        do: {:error, :not_found}

      @impl true
      def fetch_icon(_adaptor_name, _version),
        do: {:error, :not_implemented}
    end

    defmodule CachexFailingStrategy do
      @behaviour Lightning.Adaptors.Strategy

      @impl true
      def fetch_packages(_config) do
        {:error, :network_timeout}
      end

      @impl true
      def fetch_versions(_config, _adaptor_name) do
        {:error, :not_found}
      end

      @impl true
      def fetch_configuration_schema(_adaptor_name) do
        {:error, :not_implemented}
      end

      @impl true
      def fetch_icon(_adaptor_name, _version) do
        {:error, :not_implemented}
      end
    end

    test "populates cache with multiple adaptors, their versions, and schemas",
         %{schemas: schemas} do
      config = %{
        strategy: {CachexIntegrationStrategy, [config: "integration_test"]},
        cache: :warmer_integration_test
      }

      start_supervised!(
        {Cachex,
         [
           :warmer_integration_test,
           [
             warmers: [
               warmer(
                 state: config,
                 module: Lightning.Adaptors.Warmer,
                 required: true
               )
             ]
           ]
         ]}
      )

      # Verify cache contents
      {:ok, adaptors_list} = Cachex.get(:warmer_integration_test, "adaptors")
      assert adaptors_list == ["@openfn/language-foo", "@openfn/language-bar"]

      {:ok, foo_versions} =
        Cachex.get(:warmer_integration_test, "@openfn/language-foo:versions")

      assert foo_versions == %{"1.0.0" => %{"version" => "1.0.0"}}

      {:ok, bar_versions} =
        Cachex.get(:warmer_integration_test, "@openfn/language-bar:versions")

      assert bar_versions == %{
               "2.0.0" => %{"version" => "2.0.0"},
               "2.1.0" => %{"version" => "2.1.0"}
             }

      {:ok, foo_schema} =
        Cachex.get(:warmer_integration_test, "@openfn/language-foo:schema")

      assert foo_schema == schemas.foo

      {:ok, bar_schema} =
        Cachex.get(:warmer_integration_test, "@openfn/language-bar:schema")

      assert bar_schema == schemas.bar
    end

    test "gracefully handles strategy failures without crashing cache" do
      config = %{
        strategy: {CachexFailingStrategy, []},
        cache: :warmer_error_test
      }

      start_supervised!(
        {Cachex,
         [
           :warmer_error_test,
           [
             warmers: [
               warmer(
                 state: config,
                 module: Lightning.Adaptors.Warmer
               )
             ]
           ]
         ]}
      )

      {:ok, _} = Cachex.warm(:warmer_error_test, wait: true)

      # Cache should be empty since warmer returned :ignore
      {:ok, adaptors_list} = Cachex.get(:warmer_error_test, "adaptors")
      assert adaptors_list == nil
    end
  end
end
