defmodule Lightning.Credentials.Schema do
  @moduledoc """
  Structure that can parse JsonSchemas (using `ExJsonSchema`) and validate
  changesets for a given schema.
  """
  import Lightning.Utils.Maps, only: [stringify_keys: 1]

  alias Ecto.Changeset
  alias ExJsonSchema.Validator

  @type t :: %__MODULE__{
          name: String.t() | nil,
          root: ExJsonSchema.Schema.Root.t(),
          types: Ecto.Changeset.types(),
          fields: [String.t()]
        }

  defstruct [:name, :root, :types, :fields]

  @spec new(
          json_schema :: %{String.t() => any()} | binary(),
          name :: String.t() | nil
        ) ::
          __MODULE__.t()
  def new(body, name \\ nil)

  # can be ignored since not near to atom limit
  # sobelow_skip ["DOS.StringToAtom"]
  def new(json_schema, name) when is_map(json_schema) do
    fields =
      json_schema["properties"]
      # credo:disable-for-next-line
      |> Enum.map(fn {k, _v} -> k |> String.to_atom() end)

    root = ExJsonSchema.Schema.resolve(json_schema)
    types = get_types(root)

    struct!(__MODULE__, name: name, root: root, types: types, fields: fields)
  end

  def new(raw_schema, name) when is_binary(raw_schema) do
    raw_schema
    |> Jason.decode!(objects: :ordered_objects)
    |> new(name)
  end

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

  # can be ignored since not near to atom limit
  # sobelow_skip ["DOS.StringToAtom"]
  defp get_types(root) do
    root.schema
    |> Map.get("properties", [])
    |> Enum.map(fn {field, properties} ->
      # credo:disable-for-next-line
      type =
        properties
        |> Map.get("type", "string")
        |> then(fn type -> if type == "object", do: "map", else: type end)
        |> String.to_atom()

      {String.to_existing_atom(field), type}
    end)
    |> Map.new()
  end

  defp validate_json_object(value) when is_binary(value) do
    case Jason.decode(value) do
      {:ok, decoded} when is_map(decoded) -> :ok
      {:ok, _} -> :error
      {:error, _} -> :error
    end
  end

  defp validate_json_object(_), do: :error
end
