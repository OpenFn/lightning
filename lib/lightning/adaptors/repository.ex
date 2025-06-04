defmodule Lightning.Adaptors.Repository do
  @moduledoc """
  Repository module that handles the actual adaptor fetching and caching logic.

  This module contains the core implementation functions that work with configuration
  objects directly. The main Lightning.Adaptors module delegates to these functions
  after looking up configuration from the registry.
  """

  require Logger

  @doc """
  Returns a list of all adaptor names using the provided config.

  Caches both the list of names and individual adaptor details for efficient lookup.
  On first access, attempts to restore cache from disk if persist_path is configured.
  """
  def all(config) do
    # Try to restore cache from disk if persist_path is configured and cache is empty
    restore_cache_if_needed(config)

    case Cachex.fetch(config[:cache], :adaptors, fn _key ->
           {module, strategy_config} = split_strategy(config.strategy)
           {:ok, adaptors} = module.fetch_packages(strategy_config)

           # Cache individual adaptors for efficient lookup
           Enum.each(adaptors, fn adaptor ->
             Cachex.put(config[:cache], adaptor.name, adaptor)
           end)

           adaptor_names =
             adaptors
             |> Enum.map(fn adaptor ->
               adaptor.name
             end)

           # Save cache to disk after populating
           save_cache(config)

           {:commit, adaptor_names}
         end) do
      {:ok, result} ->
        result

      {:commit, result} ->
        result

      {:error, reason} ->
        Logger.warning("Cache fetch failed: #{inspect(reason)}")
        # Try direct strategy call without caching
        try do
          {module, strategy_config} = split_strategy(config.strategy)
          {:ok, adaptors} = module.fetch_packages(strategy_config)
          Enum.map(adaptors, fn adaptor -> adaptor.name end)
        rescue
          error ->
            Logger.error("Direct strategy call failed: #{inspect(error)}")
            []
        end
    end
  end

  @doc """
  Returns the list of versions for a specific adaptor using the provided config.

  If the adaptor is not cached, will populate the cache by calling all/1 first.
  Returns nil if the adaptor is not found.
  """
  def versions_for(config, module_name) do
    case Cachex.get(config[:cache], module_name) do
      {:ok, nil} ->
        # If not in cache, try to populate cache by calling all/1 first
        all(config)

        # Try again after populating cache
        case Cachex.get(config[:cache], module_name) do
          {:ok, nil} ->
            nil

          {:ok, adaptor} ->
            adaptor.versions

          {:error, reason} ->
            Logger.warning("Cache access failed: #{inspect(reason)}")
            nil
        end

      {:ok, adaptor} ->
        adaptor.versions

      {:error, reason} ->
        Logger.warning("Cache access failed: #{inspect(reason)}")
        # Try to populate cache and retry
        all(config)

        case Cachex.get(config[:cache], module_name) do
          {:ok, nil} -> nil
          {:ok, adaptor} -> adaptor.versions
          {:error, _} -> nil
        end
    end
  end

  @doc """
  Returns the latest version for a specific adaptor using the provided config.

  If the adaptor is not cached, will populate the cache by calling all/1 first.
  Returns nil if the adaptor is not found.
  """
  def latest_for(config, module_name) do
    case Cachex.get(config[:cache], module_name) do
      {:ok, nil} ->
        # If not in cache, try to populate cache by calling all/1 first
        all(config)

        # Try again after populating cache
        case Cachex.get(config[:cache], module_name) do
          {:ok, nil} ->
            nil

          {:ok, adaptor} ->
            adaptor.latest

          {:error, reason} ->
            Logger.warning("Cache access failed: #{inspect(reason)}")
            nil
        end

      {:ok, adaptor} ->
        adaptor.latest

      {:error, reason} ->
        Logger.warning("Cache access failed: #{inspect(reason)}")
        # Try to populate cache and retry
        all(config)

        case Cachex.get(config[:cache], module_name) do
          {:ok, nil} -> nil
          {:ok, adaptor} -> adaptor.latest
          {:error, _} -> nil
        end
    end
  end

  @doc """
  Saves the cache to disk if persist_path is configured.

  Returns :ok if successful or if no persist_path is configured,
  {:error, reason} if saving fails.
  """
  def save_cache(config) when is_map(config) do
    case Map.get(config, :persist_path) do
      nil ->
        :ok

      path when is_binary(path) ->
        case Cachex.save(config[:cache], path) do
          {:ok, true} ->
            Logger.debug("Adaptor cache saved to #{path}")
            :ok

          {:error, reason} = error ->
            Logger.error(
              "Failed to save adaptor cache to #{path}: #{inspect(reason)}"
            )

            error
        end

      _ ->
        Logger.warning(
          "Invalid persist_path configuration: #{inspect(config[:persist_path])}"
        )

        :ok
    end
  end

  def save_cache(_config), do: :ok

  @doc """
  Restores the cache from disk if persist_path is configured.

  Returns :ok if successful or if no persist_path is configured,
  {:error, reason} if restoration fails.
  """
  def restore_cache(config) when is_map(config) do
    case Map.get(config, :persist_path) do
      nil ->
        :ok

      path when is_binary(path) ->
        case File.exists?(path) do
          false ->
            Logger.debug("No cache file found at #{path}, skipping restore")
            :ok

          true ->
            case Cachex.restore(config[:cache], path) do
              {:ok, _} ->
                Logger.debug("Adaptor cache restored from #{path}")
                :ok

              {:error, reason} = error ->
                Logger.error(
                  "Failed to restore adaptor cache from #{path}: #{inspect(reason)}"
                )

                error
            end
        end

      _ ->
        Logger.warning(
          "Invalid persist_path configuration: #{inspect(config[:persist_path])}"
        )

        :ok
    end
  end

  def restore_cache(_config), do: :ok

  @doc """
  Clears the persisted cache file if it exists.

  Returns :ok if successful or if no persist_path is configured,
  {:error, reason} if deletion fails.
  """
  def clear_persisted_cache(config) when is_map(config) do
    case Map.get(config, :persist_path) do
      nil ->
        :ok

      path when is_binary(path) ->
        case File.rm(path) do
          :ok ->
            Logger.debug("Persisted adaptor cache cleared from #{path}")
            :ok

          {:error, :enoent} ->
            :ok

          {:error, reason} = error ->
            Logger.error(
              "Failed to clear persisted adaptor cache at #{path}: #{inspect(reason)}"
            )

            error
        end

      _ ->
        :ok
    end
  end

  def clear_persisted_cache(_config), do: :ok

  defp restore_cache_if_needed(config) do
    # Only restore if cache appears to be empty (no :adaptors key)
    case Cachex.get(config[:cache], :adaptors) do
      {:ok, nil} ->
        restore_cache(config)

      {:error, reason} ->
        Logger.warning(
          "Cache access failed during restore check: #{inspect(reason)}"
        )

        :ok

      _ ->
        :ok
    end
  end

  defp split_strategy(strategy) do
    case strategy do
      {module, config} -> {module, config}
      module -> {module, []}
    end
  end
end
