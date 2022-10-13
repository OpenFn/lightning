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

  def cron_values_to_expression(
        %{
          "weekday" => weekday,
          "hours" => hours,
          "minutes" => minutes
        } = trigger_params
      ) do
    Map.put(
      trigger_params,
      "cron_expression",
      "#{minutes} #{hours} * * #{weekday}"
    )
  end

  def cron_values_to_expression(
        %{
          "monthday" => monthday,
          "hours" => hours,
          "minutes" => minutes
        } = trigger_params
      ) do
    Map.put(
      trigger_params,
      "cron_expression",
      "#{minutes} #{hours} #{monthday} * *"
    )
  end

  def cron_values_to_expression(
        %{"hours" => hours, "minutes" => minutes} = trigger_params
      ) do
    Map.put(
      trigger_params,
      "cron_expression",
      "#{minutes} #{hours} * * *"
    )
  end

  def cron_values_to_expression(%{"minutes" => minutes} = trigger_params) do
    Map.put(
      trigger_params,
      "cron_expression",
      "#{minutes} * * * *"
    )
  end

  def cron_values_to_expression(%{"type" => _type} = trigger_params) do
    trigger_params
  end

  def cron_expression_to_values(
        %Lightning.Jobs.Trigger{
          type: type,
          cron_expression: cron_expression
        } = trigger
      )
      when type == :cron do
    rules = %{
      "hourly" => ~r/^(?<minutes>[\d]{1,2}) \* \* \* \*$/,
      "daily" => ~r/^(?<minutes>[\d]{1,2}) (?<hours>[\d]{1,2}) \* \* \*$/,
      "weekly" =>
        ~r/^(?<minutes>[\d]{1,2}) (?<hours>[\d]{1,2}) \* \* (?<weekday>[\d]{1,2})$/,
      "monthly" =>
        ~r/^(?<minutes>[\d]{1,2}) (?<hours>[\d]{1,2}) (?<monthday>[\d]{1,2}) \* \*$/
    }

    cond do
      String.match?(cron_expression, rules["hourly"]) ->
        parse_cron_expression(cron_expression, rules["hourly"], "hourly")

      String.match?(cron_expression, rules["daily"]) ->
        parse_cron_expression(cron_expression, rules["daily"], "daily")

      String.match?(cron_expression, rules["weekly"]) ->
        parse_cron_expression(cron_expression, rules["weekly"], "weekly")

      String.match?(cron_expression, rules["monthly"]) ->
        parse_cron_expression(cron_expression, rules["monthly"], "monthly")

      true ->
        Map.merge(trigger, %{"periodicity" => "custom"})
    end
  end

  def cron_expression_to_values(%Lightning.Jobs.Trigger{type: type} = trigger)
      when type != :cron,
      do: trigger

  def cron_expression_to_values(nil), do: %{}

  defp parse_cron_expression(cron_expression, rule, key),
    do:
      Regex.named_captures(rule, cron_expression)
      |> Map.merge(%{"periodicity" => key, "type" => "cron"})
end
