defmodule Lightning.Helpers do
  @moduledoc """
  Common functions for the context
  """

  @doc """
  Changes a given maps field from a json string to a map.
  If it cannot be converted, it leaves the original value
  """
  @spec coerce_json_field(map(), Map.key()) :: map()
  def coerce_json_field(attrs, field) do
    {_, attrs} =
      Map.get_and_update(attrs, field, fn body ->
        case body do
          nil ->
            :pop

          body when is_binary(body) ->
            {body, decode_and_replace(body)}

          any ->
            {body, any}
        end
      end)

    attrs
  end

  defp decode_and_replace(body) do
    case Jason.decode(body) do
      {:error, _} -> body
      {:ok, body_map} -> body_map
    end
  end
end
