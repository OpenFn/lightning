defmodule Lightning.Config.Utils do
  @moduledoc """
  Utility functions for working with the application environment.
  """

  @doc """
  Retrieve a value nested in the application environment.
  """
  def get_env([app, key | path], default \\ nil) do
    get_env(app, key, path, default)
  end

  def get_env(app, key, path, default \\ nil) do
    case Application.get_env(app, key) do
      nil -> default
      config -> get_nested(config, path, default)
    end
  end

  # Handle single key (not a list)
  defp get_nested(value, path, default) when not is_list(path) do
    get_nested(value, [path], default)
  end

  # Handle list of keys
  defp get_nested(value, [], _default), do: value

  defp get_nested(value, [head | tail], default) do
    case get_value(value, head) do
      nil -> default
      nested_value -> get_nested(nested_value, tail, default)
    end
  end

  defp get_value(value, key) when is_list(value), do: Keyword.get(value, key)
  defp get_value(value, key) when is_map(value), do: Map.get(value, key)
  defp get_value(_value, _key), do: nil

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
