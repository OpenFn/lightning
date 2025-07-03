defmodule Lightning.Adaptors.API do
  @moduledoc """
  API functions for Lightning Adaptors registry.

  This module contains the core API functions for interacting with the adaptors registry:
  - all/1: Get list of all adaptor names
  - versions_for/2: Get versions for a specific adaptor
  - latest_for/2: Get latest version for a specific adaptor
  - fetch_configuration_schema/2: Get configuration schema for an adaptor
  - save_cache/1, restore_cache/1, clear_persisted_cache/1: Cache management

  These functions use Lightning.Adaptors.Registry.config/1 to get the configuration
  for each adaptor instance.
  """

  alias Lightning.Adaptors.Repository
  require Logger

  @typedoc """
  The name of an Adaptors instance. This is used to identify instances in the
  internal registry for configuration lookup.
  """
  @type name :: term()

  @type config :: %{
          strategy: {module(), term()},
          cache: Cachex.t(),
          persist_path: String.t() | nil,
          offline_mode: boolean(),
          warm_interval: pos_integer()
        }

  @typedoc """
  Options for starting an Adaptors instance.
  """
  @type option ::
          {:name, name()}
          | {:strategy, {module(), term()}}
          | {:persist_path, String.t()}
          | {:offline_mode, boolean()}
          | {:warm_interval, pos_integer()}

  @doc """
  Returns a list of all adaptor names.

  Caches both the list of names and individual adaptor details for efficient lookup.
  On first access, attempts to restore cache from disk if persist_path is configured.

  ## Example

      # Using default instance
      adaptors = Lightning.Adaptors.API.all(Lightning.Adaptors)

      # Using named instance
      adaptors = Lightning.Adaptors.API.all(MyAdaptors)
  """
  @spec all(name()) :: {:ok, [String.t()]} | {:error, term()}
  def all(name \\ Lightning.Adaptors) do
    name
    |> Lightning.Adaptors.Registry.config()
    |> Repository.all()
  end

  @doc """
  Returns the list of versions for a specific adaptor.

  If the adaptor is not cached, will populate the cache by calling all/1 first.
  Returns nil if the adaptor is not found.

  ## Example

      # Using default instance
      versions = Lightning.Adaptors.API.versions_for(Lightning.Adaptors, "@openfn/language-http")

      # Using named instance
      versions = Lightning.Adaptors.API.versions_for(MyAdaptors, "@openfn/language-http")
  """
  @spec versions_for(name(), String.t()) :: {:ok, map()} | {:error, term()}
  def versions_for(name, module_name) do
    name
    |> Lightning.Adaptors.Registry.config()
    |> Repository.versions_for(module_name)
  end

  @doc """
  Returns the latest version for a specific adaptor.

  If the adaptor is not cached, will populate the cache by calling all/1 first.
  Returns nil if the adaptor is not found.

  ## Example

      # Using default instance
      latest = Lightning.Adaptors.API.latest_for(Lightning.Adaptors, "@openfn/language-http")

      # Using named instance
      latest = Lightning.Adaptors.API.latest_for(MyAdaptors, "@openfn/language-http")
  """
  @spec latest_for(name(), String.t()) :: {:ok, map()} | {:error, term()}
  def latest_for(name, module_name) do
    name
    |> Lightning.Adaptors.Registry.config()
    |> Repository.latest_for(module_name)
  end

  @doc """
  Fetches configuration schema for a specific adaptor.

  ## Example

      schema = Lightning.Adaptors.API.fetch_configuration_schema(Lightning.Adaptors, "@openfn/language-http")
  """
  @spec fetch_configuration_schema(name(), String.t()) ::
          {:ok, map()} | {:error, term()}
  def fetch_configuration_schema(name, module_name) do
    name
    |> Lightning.Adaptors.Registry.config()
    |> Repository.fetch_configuration_schema(module_name)
  end

  @doc """
  Saves the cache to disk if persist_path is configured.

  Returns :ok if successful or if no persist_path is configured,
  {:error, reason} if saving fails.
  """
  @spec save_cache(name()) :: :ok | {:error, term()}
  def save_cache(name \\ Lightning.Adaptors) do
    name
    |> Lightning.Adaptors.Registry.config()
    |> Repository.save_cache()
  end

  @doc """
  Restores the cache from disk if persist_path is configured.

  Returns :ok if successful or if no persist_path is configured,
  {:error, reason} if restoration fails.
  """
  @spec restore_cache(name()) :: :ok | {:error, term()}
  def restore_cache(name \\ Lightning.Adaptors) do
    name
    |> Lightning.Adaptors.Registry.config()
    |> Repository.restore_cache()
  end

  @doc """
  Clears the persisted cache file if it exists.

  Returns :ok if successful or if no persist_path is configured,
  {:error, reason} if deletion fails.
  """
  @spec clear_persisted_cache(name()) :: :ok | {:error, term()}
  def clear_persisted_cache(name \\ Lightning.Adaptors) do
    name
    |> Lightning.Adaptors.Registry.config()
    |> Repository.clear_persisted_cache()
  end
end
