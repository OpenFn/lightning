defmodule Lightning.Utils.Maps do
  @moduledoc false

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
end
