defmodule Lightning.Adaptors.Warmer do
  @moduledoc """
  Proactive cache warmer for Lightning adaptors.

  This warmer fetches adaptors from the configured strategy and populates the cache
  with adaptor names, versions, and configuration schemas. This ensures efficient
  operation without cache misses for adaptor-related functions.

  ## Usage Example

      import Cachex.Spec

      # Define your config
      config = %{
        strategy: {Lightning.Adaptors.NPM, [user: "openfn"]},
        cache: :my_adaptors_cache,
        persist_path: "/path/to/cache.bin"  # Optional persistence
      }

      # Start cache with warmer
      Cachex.start_link(:my_adaptors_cache, [
        warmers: [
          warmer(
            state: config,
            module: Lightning.Adaptors.Warmer,
            interval: :timer.minutes(5),  # Refresh every 5 minutes
            required: true                # Block startup until first successful run
          )
        ]
      ])

  After the warmer runs, your cache will contain:
  - `"adaptors"` key with a list of all adaptor names
  - `"<adaptor_name>:versions"` keys with version information for each adaptor
  - `"<adaptor_name>:schema"` keys with configuration schemas for each adaptor

  This allows `Lightning.Adaptors.all/1`, `Lightning.Adaptors.versions_for/2`, and
  `Lightning.Adaptors.fetch_configuration_schema/2` to operate efficiently without
  cache misses.

  If `persist_path` is configured, the cache will also be saved to disk after population.
  """

  use Cachex.Warmer

  @doc """
  Executes the cache warmer with the provided config.

  Takes a config map containing the strategy and cache configuration,
  fetches adaptors from the strategy, and returns pairs for caching.

  ## Parameters
    - config: A map with keys:
      - :strategy - {module, strategy_config} tuple or just module
      - :cache - Cachex cache reference (not used in warmer, but part of config)
      - :persist_path - Optional path for cache persistence

  ## Returns
    - {:ok, pairs} where pairs is a list of {key, value} tuples for caching
    - :ignore if an error occurs during fetching
  """
  @spec execute(config :: Lightning.Adaptors.API.config()) ::
          {:ok, list({String.t(), any()})} | :ignore
  def execute(config) do
    {module, strategy_config} = split_strategy(config.strategy)

    with :ok <- validate_module(module),
         {:ok, adaptors} <- module.fetch_packages(strategy_config) do
      cache_pairs =
        adaptors
        |> Task.async_stream(
          fn module_name ->
            versions_pair =
              Task.async(fn ->
                {"#{module_name}:versions",
                 fetch({module, :fetch_versions}, [strategy_config, module_name])}
              end)

            schema_pair =
              Task.async(fn ->
                {"#{module_name}:schema",
                 fetch({module, :fetch_configuration_schema}, [module_name])}
              end)

            [versions_pair, schema_pair]
            |> Task.await_many(:timer.seconds(60))
          end,
          max_concurrency: 10,
          timeout: :timer.seconds(60)
        )
        |> Stream.filter(&match?({:ok, _}, &1))
        |> Stream.flat_map(fn {_, result} ->
          result
        end)
        |> Stream.concat([{"adaptors", adaptors}])
        |> Enum.to_list()

      # TODO: add persistence after the cache is populated
      # Save cache to disk asynchronously if persistence is configured
      # This will run after the warmer has finished populating the cache
      # if Map.has_key?(config, :persist_path) and
      #      not is_nil(config.persist_path) do
      #   Task.start(fn ->
      #     # Small delay to ensure cache is fully populated
      #     Process.sleep(500)
      #     Lightning.Adaptors.save_cache(config)
      #   end)
      # end

      {:ok, cache_pairs}
    else
      {:error, _reason} ->
        :ignore
    end
  end

  defp split_strategy(strategy) do
    case strategy do
      {module, config} -> {module, config}
      module -> {module, []}
    end
  end

  defp fetch({mod, func}, args) do
    case apply(mod, func, args) do
      {:ok, result} -> result
      {:error, reason} -> {:ignore, reason}
    end
  end

  defp validate_module(module) do
    with true <- Code.ensure_loaded?(module) || {:error, :module_not_found},
         true <-
           function_exported?(module, :fetch_packages, 1) ||
             {:error, :function_not_exported} do
      :ok
    end
  end
end
