defmodule Lightning.Adaptors.WarmerTest do
  use ExUnit.Case, async: true

  import Cachex.Spec
  alias Lightning.Adaptors.Warmer

  describe "execute/1" do
    defmodule MockStrategySuccess do
      @behaviour Lightning.Adaptors.Strategy
      def fetch_packages(_config) do
        {:ok,
         [
           %Lightning.Adaptors.Package{
             name: "@openfn/language-dhis2",
             repo: "git+https://github.com/OpenFn/language-dhis2.git",
             latest: "3.2.8",
             versions: [
               %{version: "3.2.0"},
               %{version: "3.2.8"}
             ]
           }
         ]}
      end

      def fetch_credential_schema(_name),
        do: {:error, :not_implemented}

      def fetch_icon(_name, _version), do: {:error, :not_implemented}
    end

    defmodule MockStrategyFailure do
      @behaviour Lightning.Adaptors.Strategy
      def fetch_packages(_config) do
        {:error, "Something bad happened"}
      end

      def fetch_credential_schema(_name),
        do: {:error, :not_implemented}

      def fetch_icon(_name, _version), do: {:error, :not_implemented}
    end

    test "returns cache pairs for adaptors list and individual adaptors on success" do
      config = %{
        strategy: {MockStrategySuccess, [config: "test"]},
        cache: :test_cache
      }

      result = Warmer.execute(config)

      assert {:ok, pairs} = result
      # :adaptors key + 1 individual adaptor
      assert length(pairs) == 2

      # Check the :adaptors key pair
      adaptors_pair = List.first(pairs)

      assert {:adaptors, ["@openfn/language-dhis2"]} =
               adaptors_pair

      # Check individual adaptor pairs
      remaining_pairs = Enum.drop(pairs, 1)

      assert {"@openfn/language-dhis2",
              %Lightning.Adaptors.Package{
                name: "@openfn/language-dhis2",
                repo: "git+https://github.com/OpenFn/language-dhis2.git",
                latest: "3.2.8",
                versions: [
                  %{version: "3.2.0"},
                  %{version: "3.2.8"}
                ]
              }} in remaining_pairs
    end

    test "works with strategy module without config tuple" do
      config = %{
        strategy: MockStrategySuccess,
        cache: :test_cache
      }

      result = Warmer.execute(config)

      assert {:ok, pairs} = result
      assert length(pairs) == 2

      # Verify the :adaptors key is present
      adaptors_pair = List.first(pairs)

      assert {:adaptors, ["@openfn/language-dhis2"]} =
               adaptors_pair
    end

    test "returns :ignore when strategy returns error" do
      config = %{
        strategy: {MockStrategyFailure, []},
        cache: :test_cache
      }

      result = Warmer.execute(config)

      assert result == :ignore
    end

    test "returns :ignore when strategy module raises exception" do
      config = %{
        strategy: {NonExistentModule, []},
        cache: :test_cache
      }

      result = Warmer.execute(config)

      assert result == :ignore
    end

    test "handles empty adaptor list" do
      defmodule EmptyAdaptorStrategy do
        @behaviour Lightning.Adaptors.Strategy

        def fetch_packages(_config) do
          {:ok, []}
        end

        def fetch_credential_schema(_adaptor_name) do
          {:error, :not_implemented}
        end

        def fetch_icon(_adaptor_name, _version) do
          {:error, :not_implemented}
        end
      end

      config = %{
        strategy: {EmptyAdaptorStrategy, []},
        cache: :test_cache
      }

      result = Warmer.execute(config)

      assert {:ok, pairs} = result
      # Only the :adaptors key
      assert length(pairs) == 1
      assert [{:adaptors, []}] = pairs
    end
  end

  describe "integration with Cachex" do
    defmodule IntegrationMockAdaptorStrategy do
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

      def fetch_credential_schema(_adaptor_name) do
        {:error, :not_implemented}
      end

      def fetch_icon(_adaptor_name, _version) do
        {:error, :not_implemented}
      end
    end

    defmodule IntegrationMockFailingAdaptorStrategy do
      @behaviour Lightning.Adaptors.Strategy

      def fetch_packages(_config) do
        {:error, :network_timeout}
      end

      def fetch_credential_schema(_adaptor_name) do
        {:error, :not_implemented}
      end

      def fetch_icon(_adaptor_name, _version) do
        {:error, :not_implemented}
      end
    end

    test "can be used as a Cachex warmer to populate cache" do
      config = %{
        strategy: {IntegrationMockAdaptorStrategy, [config: "integration_test"]},
        cache: :warmer_integration_test
      }

      # Start cache with warmer configured
      start_supervised!(
        {Cachex,
         [
           :warmer_integration_test,
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

      # Trigger the warmer and wait for completion
      {:ok, _} = Cachex.warm(:warmer_integration_test, wait: true)

      # Verify cache contents
      {:ok, adaptors_list} = Cachex.get(:warmer_integration_test, :adaptors)
      assert adaptors_list == ["@openfn/language-foo", "@openfn/language-bar"]

      {:ok, foo_adaptor} =
        Cachex.get(:warmer_integration_test, "@openfn/language-foo")

      assert foo_adaptor.name == "@openfn/language-foo"
      assert foo_adaptor.latest == "1.0.0"

      {:ok, bar_adaptor} =
        Cachex.get(:warmer_integration_test, "@openfn/language-bar")

      assert bar_adaptor.name == "@openfn/language-bar"
      assert bar_adaptor.latest == "2.1.0"
    end

    test "warmer handles strategy errors gracefully" do
      config = %{
        strategy: {IntegrationMockFailingAdaptorStrategy, []},
        cache: :warmer_error_test
      }

      # Start cache with failing warmer configured
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

      # Trigger the warmer - should not crash despite the error
      {:ok, _} = Cachex.warm(:warmer_error_test, wait: true)

      # Cache should be empty since warmer returned :ignore
      {:ok, adaptors_list} = Cachex.get(:warmer_error_test, :adaptors)
      assert adaptors_list == nil
    end
  end
end
