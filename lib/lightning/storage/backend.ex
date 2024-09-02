defmodule Lightning.Storage.Backend do
  @moduledoc """
  The behaviour for storage backends.
  """
  @callback store(source :: String.t(), dest :: String.t()) ::
              {:ok, any()} | {:error, any()}
  @callback get_url(String.t()) :: {:ok, String.t()} | {:error, any()}
end
