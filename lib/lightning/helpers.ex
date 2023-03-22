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

  @doc """
  Converts milliseconds (integer) to a human duration, such as "1 minute" or
  "45 years, 6 months, 5 days, 21 hours, 12 minutes, 34 seconds" using
  `Timex.Format.Duration.Formatters.Humanized.format()`.
  """
  @spec ms_to_human(integer) :: String.t() | {:error, :invalid_duration}
  def ms_to_human(milliseconds) do
    milliseconds
    |> Timex.Duration.from_milliseconds()
    |> Timex.Format.Duration.Formatters.Humanized.format()
  end

  def indefinite_article(noun) do
    first_letter = String.first(noun) |> String.downcase()
    if Enum.member?(["a", "e", "i", "o", "u"], first_letter), do: "an", else: "a"
  end
end
