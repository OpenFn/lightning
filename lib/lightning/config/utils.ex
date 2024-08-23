defmodule Lightning.Config.Utils do
  @moduledoc """
  Utility functions for working with the application environment.
  """

  @doc """
  Retrieve a value nested in the application environment.
  """
  @spec get_env([atom()] | atom(), any()) :: any()
  def get_env(_keys, default \\ nil)

  def get_env([app, key, item], default) do
    Application.get_env(app, key, []) |> Keyword.get(item, default)
  end

  def get_env([app, key], default) do
    Application.get_env(app, key, default)
  end

  @spec ensure_boolean(binary()) :: boolean()
  def ensure_boolean(value) do
    case value do
      "true" ->
        true

      "yes" ->
        true

      "false" ->
        false

      "no" ->
        false

      _other ->
        raise ArgumentError,
              "expected true, false, yes or no, got: #{inspect(value)}"
    end
  end
end
