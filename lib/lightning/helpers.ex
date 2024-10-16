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

  def actual_deletion_date(
        grace_period,
        cron_expression \\ "4 2 * * *",
        unit \\ :days
      ) do
    now = Timex.now()

    due_date =
      if grace_period,
        do: now |> Timex.shift([{unit, grace_period}]) |> DateTime.to_naive(),
        else: now |> DateTime.to_naive()

    {:ok, cron_expression} = Crontab.CronExpression.Parser.parse(cron_expression)

    Crontab.Scheduler.get_next_run_date!(cron_expression, due_date)
  end

  def format_date(date, formatter \\ "%a %d/%m/%Y at %H:%M:%S") do
    Timex.Format.DateTime.Formatters.Strftime.format!(date, formatter)
  end

  @doc """
  Recursively ensures a given map is safe to convert to JSON,
  where all keys are strings and all values are json safe (primitive values).
  """
  def json_safe(nil), do: nil

  def json_safe(data) when is_struct(data) do
    data |> Map.from_struct() |> json_safe()
  end

  def json_safe(map) when is_map(map) do
    map
    |> Enum.map(fn {k, v} -> {json_safe(k), json_safe(v)} end)
    |> Enum.into(%{})
  end

  def json_safe([head | rest]) do
    [json_safe(head) | json_safe(rest)]
  end

  def json_safe(a) when is_atom(a) and not is_boolean(a), do: Atom.to_string(a)

  def json_safe(any), do: any

  @doc """
  Copies an error from one key to another in the given changeset.

  ## Parameters

    - `changeset`: The changeset to modify.
    - `original_key`: The key where the error currently exists.
    - `new_key`: The key where the error should be duplicated.
    - `opts`: A keyword list of options. Supports `overwrite`, which is a boolean indicating whether to overwrite the `new_key` error if it already exists. Defaults to `true`.

  ## Example

      iex> changeset = %Ecto.Changeset{errors: [name: {"has already been taken", []}]}
      iex> updated_changeset = Lightning.Helpers.copy_error(changeset, :name, :raw_name)
      iex> updated_changeset.errors
      [name: {"has already been taken", []}, raw_name: {"has already been taken", []}]

  If the `original_key` doesn't exist in the errors, or if the `new_key` already exists and `overwrite` is set to `false`, the changeset is returned unchanged.
  """
  def copy_error(changeset, original_key, new_key, opts \\ [overwrite: true]) do
    overwrite = Keyword.get(opts, :overwrite, true)

    if Keyword.has_key?(changeset.errors, original_key) do
      {error_msg, error_opts} = Keyword.fetch!(changeset.errors, original_key)

      if Keyword.has_key?(changeset.errors, new_key) and not overwrite do
        changeset
      else
        Ecto.Changeset.add_error(changeset, new_key, error_msg, error_opts)
      end
    else
      changeset
    end
  end
end
