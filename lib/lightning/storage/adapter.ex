defmodule Lightning.Storage.Adapter do
  @callback store(source :: String.t(), dest :: String.t()) ::
              {:ok, any()} | {:error, any()}
  @callback get(String.t()) :: {:ok, String.t()} | {:error, any()}
end
