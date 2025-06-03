defmodule Lightning.Adaptors.WarmerTest do
  use ExUnit.Case, async: true

  import Cachex.Spec
  alias Lightning.Adaptors.Warmer

  describe "execute/1" do
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

    defmodule MockFailingAdaptorStrategy do
      @behaviour Lightning.Adaptors.Strategy

      def fetch_adaptors(_config) do
        {:error, :network_timeout}
      end

      def fetch_credential_schema(_adaptor_name, _version) do
        {:error, :not_implemented}
      end

      def fetch_icon(_adaptor_name, _version) do
        {:error, :not_implemented}
      end
    end

    test "returns cache pairs for adaptors list and individual adaptors on success" do
      config = %{
        strategy: {MockAdaptorStrategy, [config: "test"]},
        cache: :test_cache
      }

      result = Warmer.execute(config)

      assert {:ok, pairs} = result
      # :adaptors key + 2 individual adaptors
      assert length(pairs) == 3

      # Check the :adaptors key pair
      adaptors_pair = List.first(pairs)

      assert {:adaptors, ["@openfn/language-foo", "@openfn/language-bar"]} =
               adaptors_pair

      # Check individual adaptor pairs
      remaining_pairs = Enum.drop(pairs, 1)

      assert {"@openfn/language-foo",
              %Lightning.Adaptors.Package{
                name: "@openfn/language-foo",
                repo: "https://github.com/openfn/foo",
                latest: "1.0.0",
                versions: [%{version: "1.0.0"}]
              }} in remaining_pairs

      assert {"@openfn/language-bar",
              %Lightning.Adaptors.Package{
                name: "@openfn/language-bar",
                repo: "https://github.com/openfn/bar",
                latest: "2.1.0",
                versions: [%{version: "2.0.0"}, %{version: "2.1.0"}]
              }} in remaining_pairs
    end

    test "works with strategy module without config tuple" do
      config = %{
        strategy: MockAdaptorStrategy,
        cache: :test_cache
      }

      result = Warmer.execute(config)

      assert {:ok, pairs} = result
      assert length(pairs) == 3

      # Verify the :adaptors key is present
      adaptors_pair = List.first(pairs)

      assert {:adaptors, ["@openfn/language-foo", "@openfn/language-bar"]} =
               adaptors_pair
    end

    test "returns :ignore when strategy returns error" do
      config = %{
        strategy: {MockFailingAdaptorStrategy, []},
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

        def fetch_adaptors(_config) do
          {:ok, []}
        end

        def fetch_credential_schema(_adaptor_name, _version) do
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

    defmodule IntegrationMockFailingAdaptorStrategy do
      @behaviour Lightning.Adaptors.Strategy

      def fetch_adaptors(_config) do
        {:error, :network_timeout}
      end

      def fetch_credential_schema(_adaptor_name, _version) do
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
