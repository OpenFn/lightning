defmodule Lightning.Adaptors.Strategy do
  @moduledoc """
  Behaviour for adaptor registry strategies (NPM, local, etc).
  """

  @callback fetch_packages(config :: term()) :: {:ok, [map()]} | {:error, term()}
  @callback fetch_versions(config :: term(), package_name :: String.t()) ::
              {:ok, [String.t()]} | {:error, term()}
  @callback validate_config(config :: term()) ::
              {:ok, keyword()} | {:error, term()}
  @callback fetch_configuration_schema(adaptor_name :: String.t()) ::
              {:ok, map()} | {:error, term()}
  @callback fetch_icon(adaptor_name :: String.t(), version :: String.t()) ::
              {:ok, binary()} | {:error, term()}

  @optional_callbacks validate_config: 1
end
