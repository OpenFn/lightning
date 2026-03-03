defmodule Lightning.Helpers do
  @moduledoc """
  Common functions for the context
  """

  alias Timex.Format.DateTime.Formatters.Strftime

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

  @doc """
  Formats a datetime in a user-friendly relative format (e.g., "2 hours ago").
  Falls back to absolute format if relative formatting fails.

  For absolute formatting, you can pass a strftime formatter string.
  """
  def format_date(date, formatter \\ :relative) do
    case formatter do
      :relative ->
        case Timex.Format.DateTime.Formatters.Relative.format(date, "{relative}") do
          {:ok, relative_time} -> relative_time
          {:error, _} -> Strftime.format!(date, "%F %T")
        end

      formatter_string when is_binary(formatter_string) ->
        Strftime.format!(date, formatter_string)
    end
  end

  def format_date_long(date) do
    Strftime.format!(
      date,
      "%A, %B %d, %Y at %H:%M %Z"
    )
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

  @doc """
  Converts a string into a URL-safe format by converting it to lowercase,
  replacing unwanted characters with hyphens, and trimming leading/trailing hyphens.

  This function allows international characters, which will be automatically
  percent-encoded in URLs by browsers.

  ## Parameters

    - `name`: The string to convert. If `nil` is passed, it returns an empty string.

  ## Examples

      iex> url_safe_name("My Project!!")
      "my-project"

      iex> url_safe_name(nil)
      ""
  """
  @spec url_safe_name(String.t() | nil) :: String.t()
  def url_safe_name(nil), do: ""

  def url_safe_name(name) when is_binary(name) do
    name
    |> String.downcase()
    |> String.replace(~r/[^\p{L}0-9_\.\-]+/u, "-")
    |> String.trim("-")
  end

  @doc """
  Derives `"name"` from `"raw_name"` in form params so that context functions
  (which cast `:name`, not `:raw_name`) receive the correct URL-safe value
  without relying on hidden-field timing.
  """
  @spec derive_name_param(map()) :: map()
  def derive_name_param(%{"raw_name" => raw_name} = params) do
    Map.put(params, "name", url_safe_name(raw_name))
  end

  def derive_name_param(params), do: params

  @doc """
  Normalizes all map keys to strings recursively.

  This function walks through a map and converts all keys to strings using `to_string/1`.
  If a key's value is also a map, it recursively normalizes the nested map as well.
  Non-map values are returned unchanged.

  ## Examples

      iex> normalize_keys(%{foo: "bar", baz: %{qux: 123}})
      %{"foo" => "bar", "baz" => %{"qux" => 123}}

      iex> normalize_keys(%{1 => "one", 2 => "two"})
      %{"1" => "one", "2" => "two"}

      iex> normalize_keys("not a map")
      "not a map"

  ## Parameters
    - `map`: The map whose keys should be normalized to strings
    - `value`: Any non-map value that should be returned as-is

  ## Returns
    - A new map with all keys converted to strings (for map inputs)
    - The original value unchanged (for non-map inputs)
  """
  def normalize_keys(map) when is_map(map) do
    Enum.reduce(map, %{}, fn
      {k, v}, acc when is_map(v) ->
        Map.put(acc, to_string(k), normalize_keys(v))

      {k, v}, acc ->
        Map.put(acc, to_string(k), v)
    end)
  end

  def normalize_keys(value), do: value
end
