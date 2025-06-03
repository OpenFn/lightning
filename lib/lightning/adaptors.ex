defmodule Lightning.Adaptors do
  @moduledoc """
  Adaptor registry

  This module provides a strategy-based adaptor registry that can fetch adaptors
  from different sources (NPM, local repositories, etc.) and cache them efficiently.

  ## Caching Strategy

  The registry uses a two-level caching approach:
  1. Individual adaptors are cached by their name for efficient lookup
  2. A list of all adaptor names is cached under the `:adaptors` key

  This allows both fast listing (for AdaptorPicker) and fast individual lookups
  (for versions_for/latest_for functions).
  """

  @type config :: %{
          strategy: {module(), term()},
          cache: Cachex.t()
        }

  @doc """
  Returns a list of all adaptor names.

  Caches both the list of names and individual adaptor details for efficient lookup.
  """
  def all(config \\ %{}) do
    {_, result} =
      Cachex.fetch(config[:cache], :adaptors, fn _key ->
        {module, strategy_config} = split_strategy(config.strategy)
        {:ok, adaptors} = module.fetch_adaptors(strategy_config)

        # Cache individual adaptors for efficient lookup
        Enum.each(adaptors, fn adaptor ->
          Cachex.put(config[:cache], adaptor.name, adaptor)
        end)

        adaptor_names =
          adaptors
          |> Enum.map(fn adaptor ->
            adaptor.name
          end)

        {:commit, adaptor_names}
      end)

    result
  end

  @doc """
  Returns the list of versions for a specific adaptor.

  If the adaptor is not cached, will populate the cache by calling all/1 first.
  Returns nil if the adaptor is not found.
  """
  def versions_for(config \\ %{}, module_name) do
    case Cachex.get(config[:cache], module_name) do
      {:ok, nil} ->
        # If not in cache, try to populate cache by calling all/1 first
        all(config)

        # Try again after populating cache
        case Cachex.get(config[:cache], module_name) do
          {:ok, nil} -> nil
          {:ok, adaptor} -> adaptor.versions
        end

      {:ok, adaptor} ->
        adaptor.versions
    end
  end

  @doc """
  Returns the latest version for a specific adaptor.

  If the adaptor is not cached, will populate the cache by calling all/1 first.
  Returns nil if the adaptor is not found.
  """
  def latest_for(config \\ %{}, module_name) do
    case Cachex.get(config[:cache], module_name) do
      {:ok, nil} ->
        # If not in cache, try to populate cache by calling all/1 first
        all(config)

        # Try again after populating cache
        case Cachex.get(config[:cache], module_name) do
          {:ok, nil} -> nil
          {:ok, adaptor} -> adaptor.latest
        end

      {:ok, adaptor} ->
        adaptor.latest
    end
  end

  defp split_strategy(strategy) do
    case strategy do
      {module, config} -> {module, config}
      module -> {module, []}
    end
  end

  def packages_filter(name) do
    name not in [
      "@openfn/language-devtools",
      "@openfn/language-template",
      "@openfn/language-fhir-jembi",
      "@openfn/language-collections"
    ] &&
      Regex.match?(~r/@openfn\/language-\w+/, name)
  end
end
