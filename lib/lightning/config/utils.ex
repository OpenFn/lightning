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

  @doc """
  Parse a comma-separated list of hostnames into a normalised list.

  Each entry is trimmed, downcased and has a single trailing dot stripped, so
  operators get the same normalisation the egress guard applies at match time.
  Empty or whitespace-only input returns `[]`.

  Raises `ArgumentError`, naming every offending entry, when any entry is empty
  or looks like something other than a bare hostname: a scheme (`://`), a path
  (`/`), an `@`, or internal whitespace. Bad entries are never silently dropped.

  Colon-bearing forms (host:port, bracketed IPv6 literals) are passed through
  untouched.
  """
  @spec parse_host_list(binary()) :: [binary()]
  def parse_host_list(value) when is_binary(value) do
    case String.trim(value) do
      "" ->
        []

      trimmed ->
        entries =
          trimmed |> String.split(",", trim: true) |> Enum.map(&String.trim/1)

        case Enum.reject(entries, &valid_host?/1) do
          [] ->
            Enum.map(entries, &normalise_host/1)

          bad ->
            raise ArgumentError,
                  "invalid host(s) #{inspect(bad)} in host list #{inspect(value)}; " <>
                    "each entry must be a bare hostname without scheme, path, " <>
                    "whitespace, or '@'"
        end
    end
  end

  defp valid_host?(""), do: false

  defp valid_host?(entry) do
    not (String.contains?(entry, ["://", "/", "@"]) or
           Regex.match?(~r/\s/, entry))
  end

  defp normalise_host(entry) do
    entry |> String.downcase() |> String.replace_suffix(".", "")
  end
end
