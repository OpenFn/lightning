defmodule Lightning.Utils.Maps do
  @moduledoc false

  @doc """
  Converts map keys from atoms to strings (shallow, top-level only).

  Raises if a nil key is encountered.

  ## Examples

      iex> stringify_keys(%{name: "John", age: 30})
      %{"name" => "John", "age" => 30}

      iex> stringify_keys(%{"already" => "string"})
      %{"already" => "string"}
  """
  def stringify_keys(map) when is_map(map) do
    Enum.into(map, %{}, fn
      {key, _value} when is_nil(key) ->
        raise "Cannot stringify a map with a nil key"

      {key, value} when is_atom(key) ->
        {key |> to_string(), value}

      {key, value} when is_binary(key) ->
        {key, value}
    end)
  end

  @doc """
  Recursively converts all map keys from atoms to strings throughout a nested structure.

  Handles:
  - Nested maps
  - Lists of maps
  - Structs (converted to maps first)

  Note: Does not perform nil key checks like `stringify_keys/1` for performance reasons.

  ## Examples

      iex> deep_stringify_keys(%{user: %{name: "John", roles: [:admin]}})
      %{"user" => %{"name" => "John", "roles" => [:admin]}}

      iex> deep_stringify_keys(%{items: [%{id: 1}, %{id: 2}]})
      %{"items" => [%{"id" => 1}, %{"id" => 2}]}

      iex> deep_stringify_keys(%User{name: "John", email: "john@example.com"})
      %{"name" => "John", "email" => "john@example.com"}
  """
  def deep_stringify_keys(%_{} = struct) do
    struct
    |> Map.from_struct()
    |> deep_stringify_keys()
  end

  def deep_stringify_keys(map) when is_map(map) do
    # Note: We don't use stringify_keys/1 here to avoid iterating twice
    Map.new(map, fn {key, value} ->
      string_key = if is_atom(key), do: to_string(key), else: key
      {string_key, deep_stringify_keys(value)}
    end)
  end

  def deep_stringify_keys(list) when is_list(list) do
    Enum.map(list, &deep_stringify_keys/1)
  end

  def deep_stringify_keys(value), do: value
end
