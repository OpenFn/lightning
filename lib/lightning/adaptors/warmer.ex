defmodule Lightning.Adaptors.Warmer do
  @moduledoc """
  Proactive cache warmer for Lightning adaptors.

  This warmer fetches adaptors from the configured strategy and populates the cache
  with both a list of all adaptor names (under the :adaptors key) and individual
  adaptor details (under each adaptor's name key).

  This ensures that both Lightning.Adaptors.all/1 and Lightning.Adaptors.versions_for/2
  functions can operate efficiently without cache misses.

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
  - `:adaptors` key with a list of all adaptor names
  - Individual keys for each adaptor (e.g., `"@openfn/language-common"`)

  This allows `Lightning.Adaptors.all/1` to return immediately from cache, and
  `Lightning.Adaptors.versions_for/2` to avoid triggering cache population on every call.

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
  def execute(config) do
    try do
      {module, strategy_config} = split_strategy(config.strategy)

      case module.fetch_packages(strategy_config) do
        {:ok, adaptors} ->
          # Create pairs for individual adaptors
          adaptor_pairs =
            Enum.map(adaptors, fn adaptor ->
              {adaptor.name, adaptor}
            end)

          # Create the list of adaptor names for the :adaptors key
          adaptor_names = Enum.map(adaptors, & &1.name)
          adaptors_list_pair = {:adaptors, adaptor_names}

          # Return all pairs together
          result = {:ok, [adaptors_list_pair | adaptor_pairs]}

          # Save cache to disk asynchronously if persistence is configured
          # This will run after the warmer has finished populating the cache
          if Map.has_key?(config, :persist_path) and
               not is_nil(config.persist_path) do
            Task.start(fn ->
              # Small delay to ensure cache is fully populated
              Process.sleep(500)
              Lightning.Adaptors.save_cache(config)
            end)
          end

          result

        {:error, _reason} ->
          :ignore
      end
    rescue
      _error ->
        :ignore
    end
  end

  defp split_strategy(strategy) do
    case strategy do
      {module, config} -> {module, config}
      module -> {module, []}
    end
  end
end
