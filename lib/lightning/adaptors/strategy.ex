defmodule Lightning.Adaptors.Strategy do
  @moduledoc """
  Behaviour for adaptor registry strategies (NPM, local, etc).
  """

  @callback fetch_adaptors(config :: map()) :: {:ok, [map()]} | {:error, term()}
  @callback fetch_credential_schema(
              adaptor_name :: String.t(),
              version :: String.t()
            ) :: {:ok, map()} | {:error, term()}
  @callback fetch_icon(adaptor_name :: String.t(), version :: String.t()) ::
              {:ok, binary()} | {:error, term()}
end
