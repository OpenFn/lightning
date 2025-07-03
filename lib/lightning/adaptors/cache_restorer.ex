defmodule Lightning.Adaptors.CacheRestorer do
  @moduledoc """
  Cache restorer that restores cache from a persisted binary file.

  This restorer attempts to read and deserialize a cache file from disk to restore
  previously cached adaptor data. This allows for fast application startup when
  a cache file exists, as the cache can be restored without needing to fetch
  fresh data from external sources.

  ## Usage Example

      import Cachex.Spec

      # Define your config with persist_path
      config = %{
        persist_path: "/path/to/cache.bin",
        cache: :my_adaptors_cache
      }

      # Start cache with cache restorer
      Cachex.start_link(:my_adaptors_cache, [
        warmers: [
          warmer(
            state: config,
            module: Lightning.Adaptors.CacheRestorer,
            required: true  # Block startup until file is read
          )
        ]
      ])

  The restorer will:
  1. Check if the persist_path file exists
  2. Read and deserialize the binary file if present
  3. Return the cached pairs for immediate cache population
  4. Return `:ignore` if file doesn't exist or can't be read

  This is typically used in combination with StrategyWarmer to provide fast
  startup when cache exists, falling back to fresh fetching when needed.
  """

  use Cachex.Warmer
  require Logger

  @doc """
  Executes the cache restorer with the provided config.

  Attempts to read and restore cache data from a binary file on disk.

  ## Parameters
    - config: A map with keys:
      - :persist_path - Path to the binary cache file
      - :cache - Cachex cache reference (not used directly by warmer)

  ## Returns
    - {:ok, pairs} where pairs is a list of {key, value} tuples restored from file
    - :ignore if file doesn't exist, can't be read, or deserialization fails
  """
  @spec execute(config :: Lightning.Adaptors.Supervisor.config()) ::
          {:ok, list({String.t(), any()})} | :ignore
  def execute(config) do
    persist_path = Map.get(config, :persist_path)

    if persist_path && File.exists?(persist_path) do
      case File.read(persist_path) do
        {:ok, binary_data} ->
          try do
            pairs = :erlang.binary_to_term(binary_data)
            Logger.debug("Successfully restored cache from #{persist_path}")
            {:ok, pairs}
          rescue
            error ->
              Logger.warning(
                "Failed to deserialize cache file #{persist_path}: #{inspect(error)}"
              )

              :ignore
          end

        {:error, reason} ->
          Logger.warning(
            "Failed to read cache file #{persist_path}: #{inspect(reason)}"
          )

          :ignore
      end
    else
      if persist_path do
        Logger.debug("Cache file does not exist at #{persist_path}")
      else
        Logger.debug("No persist_path configured, skipping file restoration")
      end

      :ignore
    end
  end
end