defmodule Lightning.Credentials.Schema do
  @moduledoc """
  Structure that can parse JsonSchemas (using `ExJsonSchema`) and validate
  changesets for a given schema.
  """
  import Lightning.Utils.Maps, only: [stringify_keys: 1]

  alias Ecto.Changeset
  alias ExJsonSchema.Validator

  require Logger

  # Maps JSON Schema type names (case-insensitive) to Ecto types. Anything not
  # listed here falls back to :string with a logged warning so a malformed
  # schema can't take the credential form down.
  @type_map %{
    "string" => :string,
    "integer" => :integer,
    "number" => :float,
    "boolean" => :boolean,
    "object" => :map,
    "array" => {:array, :string},
    "null" => :string
  }

  @type t :: %__MODULE__{
          name: String.t() | nil,
          root: ExJsonSchema.Schema.Root.t(),
          types: Ecto.Changeset.types(),
          fields: [atom()],
          warnings: %{atom() => String.t()}
        }

  defstruct [:name, :root, :types, :fields, warnings: %{}]

  @spec new(
          json_schema :: %{String.t() => any()} | binary(),
          name :: String.t() | nil
        ) ::
          __MODULE__.t()
  def new(body, name \\ nil)

  # can be ignored since not near to atom limit
  # sobelow_skip ["DOS.StringToAtom"]
  def new(json_schema, name) when is_map(json_schema) do
    fields = collect_fields(json_schema)

    plain_schema = to_plain_map(json_schema)

    {sanitized, warnings} = sanitize_property_types(plain_schema, name)

    root = ExJsonSchema.Schema.resolve(sanitized)
    types = get_types(root)

    struct!(__MODULE__,
      name: name,
      root: root,
      types: types,
      fields: fields,
      warnings: warnings
    )
  end

  def new(raw_schema, name) when is_binary(raw_schema) do
    raw_schema
    |> Jason.decode!(objects: :ordered_objects)
    |> new(name)
  end

  # `Jason.decode!(objects: :ordered_objects)` returns `Jason.OrderedObject`
  # structs, so we capture field order from the original before flattening.
  defp collect_fields(json_schema) do
    case json_schema["properties"] do
      nil ->
        []

      properties ->
        # credo:disable-for-next-line
        Enum.map(properties, fn {k, _v} -> String.to_atom(k) end)
    end
  end

  defp to_plain_map(%Jason.OrderedObject{values: pairs}) do
    Map.new(pairs, fn {k, v} -> {k, to_plain_map(v)} end)
  end

  defp to_plain_map(map) when is_map(map) and not is_struct(map) do
    Map.new(map, fn {k, v} -> {k, to_plain_map(v)} end)
  end

  defp to_plain_map(list) when is_list(list) do
    Enum.map(list, &to_plain_map/1)
  end

  defp to_plain_map(other), do: other

  @spec validate(changeset :: Ecto.Changeset.t(), schema :: t()) ::
          Ecto.Changeset.t()
  def validate(changeset, schema) do
    validation =
      Validator.validate(
        schema.root,
        Changeset.apply_changes(changeset) |> stringify_keys(),
        error_formatter: false
      )

    case validation do
      :ok ->
        changeset

      {:error, errors} when is_list(errors) ->
        Enum.reduce(errors, changeset, &error_to_changeset/2)
    end
  end

  def properties(schema, field) do
    schema.root.schema
    |> Map.get("properties")
    |> Map.get(field |> to_string())
  end

  def required?(schema, field) do
    field = to_string(field)

    schema.root.schema
    |> Map.get("required", [])
    |> Enum.any?(fn required_field -> field == required_field end)
  end

  @doc """
  Returns the original (unrecognized) JSON Schema type for a field if the
  schema's type was rewritten to "string" during loading, or `nil` otherwise.
  """
  @spec warning(t(), atom() | String.t()) :: String.t() | nil
  def warning(%__MODULE__{warnings: warnings}, field) when is_atom(field) do
    Map.get(warnings, field)
  end

  def warning(schema, field) when is_binary(field) do
    warning(schema, String.to_existing_atom(field))
  rescue
    ArgumentError -> nil
  end

  defp error_to_changeset(
         %{
           error: %Validator.Error.AnyOf{invalid: alternatives}
         } = error_map,
         changeset
       ) do
    formats =
      Enum.map(alternatives, fn %{errors: [%{error: %{expected: format}}]} ->
        format
      end)

    error_map
    |> Map.put(:error, %{any_of: formats})
    |> error_to_changeset(changeset)
  end

  @error_messages %{
    "uri" => "expected to be a URI",
    "email" => "expected to be an email"
  }
  @expected_formats Map.keys(@error_messages)

  defp error_to_changeset(%{path: path, error: error}, changeset) do
    field = String.slice(path, 2..-1//1) |> String.to_existing_atom()

    handle_error(error, changeset, field)
  end

  defp handle_error(%{expected: format}, changeset, field)
       when format in @expected_formats do
    error_msg = Map.fetch!(@error_messages, format)
    Changeset.add_error(changeset, field, error_msg)
  end

  defp handle_error(%{any_of: formats}, changeset, field) do
    formatted_types =
      formats
      |> Enum.map_join(" or ", fn
        "uri" -> "a URI"
        <<"ipv", char>> -> "an IPv#{char - ?0} address"
      end)

    Changeset.add_error(changeset, field, "expected to be #{formatted_types}")
  end

  defp handle_error(%{missing: fields}, changeset, _field) do
    Enum.reduce(fields, changeset, fn field, changeset ->
      # Convert string field name to atom to match schema.fields
      field_atom = String.to_existing_atom(field)
      Changeset.add_error(changeset, field_atom, "can't be blank")
    end)
  end

  defp handle_error(%{actual: 0, expected: _}, changeset, field) do
    Changeset.add_error(changeset, field, "can't be blank")
  end

  defp handle_error(%{actual: "null", expected: expected}, changeset, field)
       when is_list(expected) do
    Changeset.add_error(changeset, field, "can't be blank")
  end

  defp handle_error(%{expected: ["object"], actual: "string"}, changeset, field) do
    value = Changeset.get_field(changeset, field)

    case validate_json_object(value) do
      :ok -> changeset
      :error -> Changeset.add_error(changeset, field, "invalid JSON")
    end
  end

  defp handle_error(%{expected: ["object"], actual: _}, changeset, field) do
    Changeset.add_error(changeset, field, "must be an object")
  end

  defp get_types(root) do
    root.schema
    |> Map.get("properties", [])
    |> Enum.map(fn {field, properties} ->
      type_string = resolve_type(properties)
      ecto_type = Map.get(@type_map, type_string, :string)
      {String.to_existing_atom(field), ecto_type}
    end)
    |> Map.new()
  end

  defp resolve_type(%{"type" => type}) when is_binary(type), do: type

  defp resolve_type(%{"anyOf" => alternatives}) when is_list(alternatives) do
    Enum.find_value(alternatives, "string", fn alt -> Map.get(alt, "type") end)
  end

  defp resolve_type(_), do: "string"

  # Walks `properties` and replaces any "type" value that isn't a known JSON
  # Schema primitive with "string". ExJsonSchema's meta-schema validation
  # rejects unknown type names outright, so this has to run before
  # `ExJsonSchema.Schema.resolve/1`. Returns `{sanitized_schema, warnings}`
  # where warnings is `%{field_atom => original_unknown_type}`.
  defp sanitize_property_types(json_schema, schema_name) do
    case Map.get(json_schema, "properties") do
      properties when is_map(properties) ->
        {sanitized_props, warnings} =
          Enum.map_reduce(properties, %{}, fn {field, prop}, acc ->
            {sanitized, unknown} = sanitize_property(prop, field, schema_name)

            acc =
              case unknown do
                nil -> acc
                type -> Map.put(acc, String.to_existing_atom(field), type)
              end

            {{field, sanitized}, acc}
          end)

        {Map.put(json_schema, "properties", Map.new(sanitized_props)), warnings}

      _ ->
        {json_schema, %{}}
    end
  end

  # Returns {sanitized_property, unknown_type_or_nil}.
  defp sanitize_property(%{"type" => type} = prop, field, schema_name)
       when is_binary(type) do
    case normalize_type_string(type, field, schema_name) do
      {:ok, normalized} -> {Map.put(prop, "type", normalized), nil}
      {:rewritten, normalized} -> {Map.put(prop, "type", normalized), type}
    end
  end

  defp sanitize_property(%{"anyOf" => alternatives} = prop, _field, schema_name)
       when is_list(alternatives) do
    sanitized =
      Enum.map(alternatives, fn alt ->
        {alt_sanitized, _unknown} = sanitize_property(alt, "anyOf", schema_name)
        alt_sanitized
      end)

    {Map.put(prop, "anyOf", sanitized), nil}
  end

  defp sanitize_property(prop, _field, _schema_name), do: {prop, nil}

  defp normalize_type_string(type, field, schema_name) do
    downcased = String.downcase(type)

    if Map.has_key?(@type_map, downcased) do
      {:ok, downcased}
    else
      report_unknown_type(type, field, schema_name)
      {:rewritten, "string"}
    end
  end

  defp report_unknown_type(type, field, schema_name) do
    message =
      "Unknown JSON Schema type #{inspect(type)} for field " <>
        "#{inspect(field)}#{schema_label(schema_name)}; " <>
        "falling back to \"string\"."

    Logger.warning(message)

    Lightning.Sentry.capture_message(message,
      level: :warning,
      tags: %{type: "credential_schema"},
      extra: %{
        schema_name: schema_name,
        field: to_string(field),
        unknown_type: type
      }
    )
  end

  defp schema_label(nil), do: ""
  defp schema_label(name), do: " in schema #{inspect(name)}"

  defp validate_json_object(value) when is_binary(value) do
    case Jason.decode(value) do
      {:ok, decoded} when is_map(decoded) -> :ok
      {:ok, _} -> :error
      {:error, _} -> :error
    end
  end

  defp validate_json_object(_), do: :error
end
